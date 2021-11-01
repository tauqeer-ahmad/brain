class Payment < ActiveRecord::Base
  GRACE_PERIOD = 5.days
  PAYMENT_PERIOD = 6.days

  serialize :params

  belongs_to :user
  belongs_to :product

  validates_presence_of :product_id
  validates_presence_of :user_id
  validates_numericality_of :price

  after_create :schedule_for_payment

  scope :sorted, :order => 'id DESC'
  scope :paid, :conditions => "state = 'paid'"
  scope :should_be_paid, :conditions => "state = 'paying'"
  scope :not_paid, :conditions => "state != 'paid'"
  scope :time_for_payment, :conditions => ["created_at < ?", PAYMENT_PERIOD.ago]

  def self.cron_pay
    self.should_be_paid.time_for_payment.first.try :pay
  end

  def subject
    "Payment from BytesMarket.com"
  end

  def note
    "For purchase of #{self.product.title.inspect} by a recent user"
  end

  def price_in_cents
    (self.price.to_f*100).to_i
  end

  def user_cannot_receieve_payment
    return if self.paid?
    self.pend!
    self.save
    PaymentMailer.user_cannot_receieve_payment_email(self).deliver
  end

  def soft_pay
    self.paid!
    self.params = {:status => "Soft pay"}
    PaymentMailer.success_email(self).deliver
    self.save
  end

  def pay
    return if self.paid?
    return user_cannot_receieve_payment unless user.can_receieve_payment?
    return soft_pay if user.from_square63?

    response = STANDARD_GATEWAY.transfer(self.price_in_cents, self.user.paypal_email, :subject => self.subject, :note => self.note, :unique_id => self.id)
    self.params = response.params
    if response.success?
      self.paid!
      PaymentMailer.success_email(self).deliver
    else
      self.failed!
    end
    self.save
  end

  def display_price
    ["$", "%.2f" % self.price.round(2)].join
  end

  def schedule_for_payment
    self.user.financials.increment :payments_count
    self.user.financials.increment :pending_amount, self.price
    self.user.financials.increment :total_amount, self.price
    self.user.financials.save
    self.user.save
    self.do_pay
    PaymentMailer.delay.schedule_email(self)
    ProductMailer.delay.admin_product_mail(self.product, self.user)
  end

  def do_pay
    self.paying!
    self.save
  end

  def paid!
    self.paid_at = Time.now.utc
    self.recipient = self.user.paypal_email
    self.user.financials.decrement :pending_amount, self.price
    self.user.financials.increment :paid_amount, self.price
    self.user.financials.save
    self.state = 'paid'
  end

  def paid?
    self.state == 'paid'
  end

  def failed!
    self.state = 'failed'
  end

  def failed?
    self.state == 'failed'
  end

  def pend!
    self.state = 'pending'
  end

  def pending?
    self.state == 'pending'
  end

  def paying!
    self.state = 'paying'
  end

  def paying?
    self.state == 'paying'
  end

  def should_pay?
    !(self.paying? || self.paid?)
  end

  def expected_payment_time
    t = self.created_at.since(PAYMENT_PERIOD)
    return t if t > Time.now.utc
    1.minute.since
  end
end
