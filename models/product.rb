class Product < ActiveRecord::Base
  MINIMUM_PRICE = 0.5
  FREE_FILE_SIZE = 1024 * 1024 * 1024 # 1024MB
  FREE_FILE_SIZE_MB = (FREE_FILE_SIZE.to_f/1024/1024).round(2)
  PERCENTAGE = 10
  BASE_AMOUNT = 0 #0.1
  PER_PAGE = 12
  MAX_IMAGES = 10
  MAX_FILES = 30
  FREE_MAX_FILES = 30 # 3

  has_and_belongs_to_many :carts
  has_many :product_tags, :class_name => 'ProductsTags'
  has_many :tags, :through => :product_tags
  has_many :product_images, :dependent => :destroy
  has_many :product_uploads, :dependent => :destroy
  has_many :images, :through => :product_images
  has_many :uploads, :through => :product_uploads
  has_many :payments
  has_many :ratings

  belongs_to :updated_product, :class_name => "Product", :foreign_key => :updated_product_id
  has_one :original_product, :class_name => "Product", :foreign_key => :updated_product_id

  belongs_to :user

  alias :files :uploads

  validate :duplicate_uploads
  validate :free_product_uploads_size
  validate :very_small_price
  validates_presence_of :title
  validates_presence_of :user_id
  validates_numericality_of :price, :allow_nil => true, :greater_than_or_equal_to => 0, :less_than => 9999999
  validates_length_of :files, :minimum => 1, :maximum => MAX_FILES, :too_short => "(atleast 1) is required", :too_long => "are too many, maximum #{MAX_FILES} allowed. Please remove a few..."
  validates_length_of :images, :maximum => MAX_IMAGES, :too_long => "are too many, maximum #{MAX_IMAGES} allowed. Please remove a few..."

  attr_protected :user_id, :state, :purchase_count, :like_count, :dislike_count, :original_price

  accepts_nested_attributes_for :images, :uploads
  #accepts_nested_attributes_for :product_tags

  scope :limited,  :limit      => PER_PAGE
  scope :to_show,  :conditions => {:state => ['pending', 'active']}
  scope :pending,  :conditions => {:state => 'pending'}
  scope :active,   :conditions => {:state => 'active'}
  scope :rejected, :conditions => {:state => 'rejected'}
  scope :init,     :conditions => {:state => 'init'}
  scope :ordered,  :order      => 'created_at DESC'
  scope :id_ordered,  :order      => 'id DESC'
  scope :updated_ordered,  :order      => 'updated_at DESC'
  scope :best,     :order      => 'like_count DESC'
  scope :eager_loaded, :include => [:uploads, :images, :tags, :payments, :user]
  scope :with_user, lambda {|user_id| {:conditions => {:user_id => user_id}}}
  scope :with_state, lambda {|state| {:conditions => {:state => state}}}

  define_index do
    indexes title
    indexes description
    indexes uploads.file_file_name, :as => :upload_file_name
    indexes uploads.file_content_type, :as => :upload_file_content_type

    has :id
    has price
    has user_id
    has created_at
    has purchase_count
    has images.photo_file_size
    has tags.id, :as => :tag_id, :facet => true
    has tags.parent_id, :as => :tag_parent_id, :facet => true
    has "state='active'", :as => :active, :type => :boolean, :facet => true
    has "count(images.id) > 0", :as => :has_image, :type => :boolean
    has "sum(uploads.file_file_size)", :as => :total_size, :type => :integer

    where "state in ('active', 'pending')"

    set_property :delta => true
    set_property :morphology => 'stem_en'
    set_property :min_prefix_len => 3
    set_property :enable_star    => true
  end

  def self.make_price_range(min, max)
    min = min.to_f
    max = max.present? && max.to_f || 9999999.9
    Range.new(min, max)
  end

  def self.make_size_range(min, max)
    min = min.to_f
    max = max.present? && max.to_f || 9999999.9
    min, max = [min*1024*1024, (max+0.004999999)*1024*1024]
    Range.new(min.to_i, max.to_i)
  end

  def our_fee
    (self.price - self.original_price).round(2)
  end

  def self.our_fee_for(new_price)
    PERCENTAGE * new_price.to_f / 100.0 + BASE_AMOUNT
  end

  def original_priced!
    return if self.price.to_f.zero?
    self[:price] = self.original_price
  end

  def url(host)
    [host, 'products', self.slug].join('/')
  end

  def self.find_by_sluggish_id(sluggish_id)
    product = self.find_by_id(sluggish_id.split('-').last)
    product && product.slug == sluggish_id && product || nil
  end

  def to_param
    self.slug
  end

  def slug
    s = self.title.parameterize if self.title.present?
    [s, self.id].compact.join('-')
  end

  def price_in_cents
    (self.price.to_f*100).to_i
  end

  def price
    self[:price].to_f.round(2)
  end

  def price=(new_price)
    self[:original_price] = !new_price.to_f.zero? && new_price.to_f || nil
    self[:price] = !new_price.to_f.zero? && (new_price.to_f + self.class.our_fee_for(new_price)).round(2) || nil
  end

  def product_tag
    self.product_tags.first || self.product_tags.build
  end

  def self.default_options
    {:with => {:active => true},
     :conditions => {},
     :star => true,
     :include => [:tags, :uploads, :images, :user],
     :order => "created_at DESC, @relevance DESC",
     :page => 1,
     :per_page => PER_PAGE,
    }
  end

  def self.field_for_order(f)
    ['price', 'created_at', 'total_size', 'purchase_count'].include?(f) && f || 'created_at'
  end

  def self.direction_for_order(d)
    ['asc', 'desc'].include?(d) && d || 'desc'
  end

  def self.perform_search(options)
    options = (options || {}).symbolize_keys_recursive

    o = self.default_options
    k = options.delete(:keyword)

    o[:with][:price] = make_price_range(options[:min_price], options[:max_price]) if options.has_key?(:min_price) || options.has_key?(:max_price)
    o[:with][:total_size] = make_size_range(options[:min_size], options[:max_size]) if options.has_key?(:min_size) || options.has_key?(:max_size)
    o[:with][:has_image] = true if options[:has_image].present?
    o[:with][:price] = (0.0..0.0) if options[:free_only].present?
    o[:with][:active] = false if options[:show_pending].present?
    o[:page] = options[:page] if options[:page].present?
    o[:per_page] = options[:per_page] if options[:per_page].present?

    if options[:tag_id].present?
      tag = Tag.find(options[:tag_id])
      tag_ids = [tag.id] + tag.children.collect(&:id)
      o[:with][:tag_id] = tag_ids
    end

    if options[:order].present?
      field, direction = options[:order].split('.')
      order = [field_for_order(field), direction_for_order(direction)].join(' ')
      o[:order] = "#{order}, @relevance DESC"
    end

    p [k,o]
    self.search k.to_proper_utf8, o
  end

  def photo_url
    ['http://', APP_CONFIG[:domain], self.photo].join
  end

  def photo?
    self.images.first.present?
  end

  def photo(style = :display)
    image = self.images.first || self.images.new
    image.photo.url(style)
  end

  def product_tags_attributes=(new_attributes)
    new_attributes[:tag_id] = self.tags.first.parent_id if new_attributes[:tag_id].blank?
    self.product_tags.each(&:destroy)
    self.product_tags.clear
    self.product_tags.build(new_attributes)
  end

  def primary_tag
    self.tags[0]
  end

  def display_title
    t = self.title.to_s.clone
    t = ["Product", self.id].join(' ') if t.blank?
    if primary_tag
      tag_name = [primary_tag.name]
      tag_name = [primary_tag.parent.name] + tag_name if primary_tag.parent
      t << " <small>(#{tag_name.join(', ')})</small>"
    end
    t
  end

  def keywords
    t = [self.title.to_s.clone]
    if primary_tag
      tag_name = [primary_tag.name]
      tag_name = [primary_tag.parent.name] + tag_name if primary_tag.parent
      t << tag_name.join(', ')
    end
    t.join(", ")
  end

  def force_save
    self.save :validate => false
  end

  def free?
    self.price.to_f.zero?
  end

  def in_cart?
    CartsProducts.exists? :product_id => self.id
  end

  def mini_title
    self.title.to_s.truncate(30)
  end

  def bought_free?(current_user)
    return false if current_user.blank?
    carts = self.carts.purchased.find_all_by_user_id(current_user.id)
    carts.present?
  end

  def total_uploads_size
    self.uploads.collect(&:file_file_size).sum
  end

  def display_original_price
    return "FREE" if self.free?
    ["$", "%.2f" % self.original_price.round(2)].join
  end

  def display_price
    return "FREE" if self.free?
    ["$", "%.2f" % self.price.round(2)].join
  end

  def init?
    self.state == 'init'
  end

  def pending?
    self.state == 'pending'
  end

  def active?
    self.state == 'active'
  end

  def rejected?
    self.state == 'rejected'
  end

  def pend!
    self.state = 'pending'
    self.save
    ProductMailer.delay.pending_mail(self)
  end

  def accept!
    self.state = 'active'
    self.save
    self.delay.generate_zip
    ProductMailer.delay.acceptance_mail(self)
  end

  def accept_and_own!
    self.user = User.find_by_email('seller_bm@square63.com') if self.user.from_square63?
    self.accept!
  end

  def reject!(reason = 'This product does not conform with our guidelines')
    self.state = 'rejected'
    self.save
    ProductMailer.delay.rejection_mail(self, reason)
  end

  def init!
    self.state = 'init'
  end

  def idle!
    self.state = 'idle'
  end

  def file_name
    [[self.title.titleize.gsub(' ', '_'), self.id].join('_'), 'zip'].join('.')
  end

  def file_content_type
    'application/zip'
  end

  def execute(command)
    `#{command}`
  end

  def generate_zip
    files = []
    tmp_dir = "/tmp/product_#{self.id}"
    FileUtils.mkdir_p tmp_dir unless Dir.exists?(tmp_dir)
    self.uploads.each do |upload|
      f_path = [tmp_dir, upload.file_name].join('/')
      files << f_path.inspect
      FileUtils.cp [Rails.root, upload.file_path].join('/'), f_path
    end
    FileUtils.mkdir_p file_dir unless Dir.exists?(self.file_dir)
    target_path = [Rails.root, self.file_path].join('/')
    execute "/usr/bin/zip -m -j #{target_path} #{files.join(' ')}"
    FileUtils.mv "#{target_path}.zip", target_path
    self.file_path
  end

  def file_dir
    Pathname(self.file_path).dirname.to_s
  end

  def full_file_path
    [Rails.root, self.file_path].join('/')
  end

  def get_file_path
    self.generate_zip unless File.exists?(self.full_file_path)
    self.file_path
  end

  def file_path
    hash = Digest::MD5.hexdigest(self.id.to_s + 'kLyMaCs!!!')
    hash_path = ''
    3.times { hash_path += '/' + hash.slice!(0..2) }
    "static/downloads/#{self.id}/" + [hash_path[1..12], hash].join('/')
  end

  def accessible_by?(user)
    return true if self.free?
    return false unless user
    return true if user.admin?
    return true if user.id == self.user_id
    return true if self.purchased_by?(user)
  end

  def purchased_by?(user)
    self.carts.purchased.find_by_user_id(user.id).present?
  end

  def default_description
    "No description"
  end

  def display_description
    return self.description if self.description.present?
    return self.default_description
  end

  def credits_over?
    self.purchase_count >= self.credits && !self.credits.zero?
  end

  def got_purchased
    self.increment :purchase_count
    self.idle! if credits_over?
    self.save
    self.payments.create :price => self.original_price, :user => self.user unless self.free?
  end

  def free_product_uploads_size
    return true unless self.free?
    self.uploads.each do |uplaod|
      self.errors[:base] = "#{uplaod.file_name} is of #{uplaod.file_size_in_mb}MB, whereas allowed file size of a free product is #{FREE_FILE_SIZE_MB}MB" if uplaod.file_size > FREE_FILE_SIZE
    end
    self.errors[:base] = "Free products support maximum of #{FREE_MAX_FILES} files, please remove #{self.uploads.size-FREE_MAX_FILES} file(s), or set a price for your product" if self.uploads.size > FREE_MAX_FILES
  end

  def duplicate_uploads
    duplicates = []

    self.uploads.group_by(&:file_fingerprint).each do |k, v|
      v[1..-1].each do |u|
        self.uploads.delete(u)
      end
    end
  end

  def very_small_price
    return true if self.free?
    self.errors[:price] = "(#{self.display_original_price}) is a very small amount. Minimum should be $#{MINIMUM_PRICE}" if self.original_price.to_f < MINIMUM_PRICE
  end

  def self.rejection_reasons
    [ 'This product does not conform with our guidelines',
      'Problem with Title',
      'Problem with Photo',
      'Problem with Description',
      'Problem with Price',
      'Problem with Category',
      'Problem with Files',
    ]
  end

  def liked_by?(user)
    rating = self.ratings.find_by_user_id(user.id)
    rating && rating.like?
  end

  def disliked_by?(user)
    rating = self.ratings.find_by_user_id(user.id)
    rating && !rating.like?
  end

  def like(user, like)
    rating = self.ratings.find_by_user_id(user.id)
    rating.destroy if rating
    self.ratings.create :user => user, :like => like, :comment => rating.rcall(:comment)
  end

  def like_comment(user, comment)
    rating = self.ratings.find_by_user_id(user.id) || self.ratings.new(:user => user, :like => true)
    rating.comment = comment
    rating.save
  end

  def deleted?
    self.state == 'deleted'
  end

  def soft_destroy
    self.state = 'deleted'
    self.save
  end

  def similar_products
    return @similar_products if @similar_products

    o = {:with => {:active => true}, :conditions => {}, :page => 1, :per_page => 10, :include => [:tags, :images], :without => {:id => self.id}}
    k = nil
    tag = self.tags.first
    @similar_products = []

    if tag.present?
      if tag.parent?
        o[:with][:tag_parent_id] = tag.id
      else
        o[:with][:tag_id] = tag.id
      end
      o[:limit] = 5
      p o
      @similar_products = self.class.search o
    end

    if @similar_products.empty?
      o[:with].delete(:tag_id)
      file_content_types = self.uploads.collect(&:file_content_type)
      o[:conditions][:upload_file_content_type] = file_content_types
      o[:limit] = 5
      p o
      @similar_products = self.class.search o if file_content_types.present?
    end

    if @similar_products.empty?
      o[:limit] = 5
      o[:conditions].delete(:upload_file_content_type)
      @similar_products = self.class.search [self.title, self.description].join(' '), o
    end

    @similar_products
  end

  def bought?
    !self.payments.empty?
  end

  def duplicate
    self.idle!
    protected_attributes = [:id, :user_id, :state, :purchase_count, :like_count, :dislike_count, :original_price]
    attributes = self.attributes.delete_if{|key, value| protected_attributes.include? key.to_sym}
    new_product = self.set_new_product(attributes)
    self.updated_product_id = new_product.id
    self.save
    new_product
  end

  def idle!
   self.state = 'idle'
   self.save
  end

  def set_new_product(attributes)
    new_product = Product.new attributes
    new_product.uploads = self.uploads
    new_product.images = self.images
    new_product.tags = self.tags
    new_product.user = self.user
    new_product.save
    new_product
  end

  def notify_free_purchase(user)
   ProductMailer.delay.free_product_mail(self, user)
   # ProductMailer.delay.admin_product_mail(self, user)
  end

end
