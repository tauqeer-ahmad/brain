class Calculator < ActiveRecord::Base
  include Snapshotable
  include Quoteable
  include Uploadable
  include Videoable
  include Sluggish
  include Archiveable
  include Recency
  include Activityable

  PER_PAGE = 20
  TYPES = %w{Maths Reference User}
  STATUSES = %w{started other development\ template draft complete\ draft final\ draft}
  ALL_STATUSES = STATUSES + %w{testing live}
  ESCAPE_MISSING_FIELDS = %w{delta deleted_at}
  DEMO_STATUSES = %w{final\ draft testing live}

  concerned_with :parser
  concerned_with :variable_parser
  concerned_with :user_sentence
  concerned_with :result_generator
  acts_as_commentable

  attr_accessible :title, :body, :category_name, :sentence,
                  :pointers, :result, :how_we_calculate, :disclaimer, :calculator_type,
                  :status, :sentence_title, :dimensions_attributes,
                  :gender, :education, :calculator_upload_attributes,
                  :misc, :min_age, :max_age, :set_as_related_calcualtor,
                  :todo, :show_notification_section, :show_in_carousel,
                  :sub_title, :calculator_facts_attributes, :poll_calculators_attributes,
                  :attachments_attributes

  has_one :category, :as => :categorical, :dependent => :destroy, :conditions => "categories.deleted_at IS NULL"
  has_many :dimensions, :class_name => "CalculatorDimension", :dependent => :destroy
  has_many :poll_calculators, :dependent => :destroy, :order => "position ASC"
  has_many :polls, :through => :poll_calculators, :order => "poll_calculators.position ASC"
  has_many :calculator_submissions, :dependent => :destroy
  has_many :library_calculators, :dependent => :destroy
  has_many :libraries, :through => :library_calculators
  has_many :calculator_notifications, :dependent => :destroy
  has_many :calculator_convenience_functions, :dependent => :destroy
  has_many :convenience_functions, :through => :calculator_convenience_functions
  has_many :signoffs, :as => :signoffable, :dependent => :destroy
  has_many :attachments, :as => :attachable
  has_one :calculator_upload, :dependent => :destroy
  has_one :upload, :through => :calculator_upload
  has_many :calculator_facts, :conditions => {:deleter_id => nil}, :order => "position ASC"
  has_many :interesting_facts, :through => :calculator_facts, :order => "calculator_facts.position ASC"
  belongs_to :user

  scope :top_five, :order => "submission_count DESC", :limit => 6
  scope :live, :conditions => {:status => "live"}
  scope :with_demo_status, :conditions => {:status => DEMO_STATUSES}
  scope :show_in_carousel, where(:show_in_carousel => true)
  scope :carousel_eager_loaded, :include => [:upload]

  accepts_nested_attributes_for :calculator_facts, :allow_destroy => true
  accepts_nested_attributes_for :dimensions, :allow_destroy => true
  accepts_nested_attributes_for :poll_calculators, :allow_destroy => true
  accepts_nested_attributes_for :attachments, :allow_destroy => true

  validates_presence_of :title, :category

  before_save :reset_signoffs
  before_save :set_convenience_functions

  alias_attribute :sub_title, :body

  serialize :content

  define_index do
    indexes title
    indexes body
    indexes result
    indexes pointers
    indexes how_we_calculate
    indexes disclaimer
    indexes interesting_facts.title, :as => :interesting_fact_title
    indexes interesting_facts.description, :as => :interesting_fact_description
    indexes :id, :as => :calc_id

    indexes category(:name), :as => :category_name
    indexes :calculator_type, :as => :type
    indexes :gender, :as => :gender

    has category.category_detail.visible, :as => :category_visible
    has "calculators.id", :as => :calculator_id, :type => :integer
    has calculator_submissions.user_id, :as => "submitter_user_id"
    has "CRC32(education)", :as => :education, :type => :integer
    has "CRC32(categories.name)", :as => :category_name_crc32, :type => :integer, :facet => true
    has "CRC32(calculators.status)", :as => :status_crc32, :type => :integer
    has "calculators.deleted_at IS NOT NULL", :as => :deleted, :type => :boolean
    has 'CHARACTER_LENGTH(IFNULL(calculators.todo, "")) > 0', :as => :todo, :type => :boolean
    has set_as_related_calcualtor, :as => :set_as_related_calcualtor, :type => :boolean
    has "COUNT(DISTINCT `signoffs`.`id`)", :as => :signoff_count, :type => :integer
    has created_at, updated_at, submission_count, min_age, max_age, share_count
    has signoffs(:id)
    set_property :delta => true
    set_property :min_prefix_len => 1
  end

  after_initialize :set_content

  def title_width_value
    return title_width if title_width.present?
    return "400"
  end

  def calculator_button_top_value
    return calculator_button_top if calculator_button_top.present?
    return "0"
  end

  def calculator_title_top_value
    return calculator_title_top if calculator_title_top.present?
    return "0"
  end

  def calculator_subtitle_top_value
    return calculator_subtitle_top if calculator_subtitle_top.present?
    return "0"
  end

  def set_content
    self.content ||= {}
  end

  def show_top_5_calculators?
    show_top_5_calculators == '1'
  end

  def user_login_required?
    user_login_required == '1'
  end

  def self.extra_fields
    ["title_width", "calculator_button_top", "calculator_title_top", "calculator_subtitle_top",
     "result_title", "user_login_required", "show_new", "show_updated", "show_top_5_calculators"
    ]
  end

  extra_fields.each do |field|
    attr_accessor field
    method_name = field.underscore.gsub(' ', '_')
    attr_accessible method_name

    define_method method_name do
      set_content
      self.content[method_name]
    end

    define_method "#{method_name}=" do |new_val|
      set_content
      self.content[method_name] = new_val
    end
  end

  def self.default_options(pagination_options)
    {:with => {:deleted => false},
     :without => {},
     :conditions => {},
     :order => "@relevance DESC, id DESC",
     :include => [:category => :category_detail],
     :page => pagination_options[:page],
     :per_page => pagination_options[:per_page] || PER_PAGE,
     :field_weights => {
       :calc_id => 50,
       :title => 15,
       :body => 8,
       :result => 7,
       :pointers => 7,
       :interesting_fact_title => 5,
       :interesting_fact_description => 5,
       :how_we_calculate => 4,
       :disclaimer => 8,
     },
    }
  end

  def self.perform_search(params, pagination_options, facet = false)
    options = self.default_options(pagination_options)
    options[:conditions][:type] = params[:types].join(' ') if params.evaluate(:types).present?
    options[:conditions][:gender] = params[:gender].collect {|s| "^#{s}$"}.join(' | ') if params[:gender].present?

    c_names = params.fetch(:category_names, []).reject(&:blank?).collect(&:to_crc32)

    options[:with][:category_name_crc32] = c_names if c_names.present?
    options[:with][:status_crc32] = params[:statuses].collect(&:to_crc32) if params.evaluate(:statuses).present?
    options[:with][:todo] = true if params[:todo].present?
    options[:with][:deleted] = true if params[:deleted].present?
    options[:with][:updated_at] = params[:updated_at].join.to_date..1.day.since.to_date if params[:updated_at].present?
    options[:with][:signoff_count] = params[:signoff_count] if params.evaluate(:signoff_count).present?
    options[:with][:set_as_related_calcualtor] = params[:set_as_related_calcualtor] if params[:set_as_related_calcualtor].present?
    options[:with][:education] = params[:education] if params[:education].present?
    options[:with][:category_visible] = true if params[:category_visible].present?
    options[:with][:cond] = true if params[:sphinx_select].present?
    options[:without][:submitter_user_id] = params[:without_submitter_user_ids] if params[:without_submitter_user_ids].present?
    options[:without][:calculator_id] = params[:without_calculator_id] if params[:without_calculator_id].present?

    options[:sphinx_select]  = params[:sphinx_select] if params[:sphinx_select].present?
    options[:order] = "#{params[:order_by]} DESC" if params[:order_by].present?
    options[:limit] = params[:limit] if params[:limit].present?

    options[:include] = [:category] if params[:nav_bar_eager_load]
    options[:include] = [:upload] if params[:carousel_eager_loaded]

    return self.facets(Riddle.escape(params[:term].to_s).to_s, options) if facet
    self.search Riddle.escape(params[:term].to_s).to_s, options
  end

  def calculator_upload_attributes=(new_attributes)
    self.build_calculator_upload new_attributes
  end

  def image
    i = self.upload || Upload.new
    i.file
  end

  def self.sphinx_select(options = {})
    o = search_select_options(options) if options[:user].present?
    o = 1 if o.blank?
    "*, #{o} as cond"
  end

  def self.search_select_options(options)
    if options[:user].present? && options[:user].get("age").present?
      return "min_age <= #{options[:user].get('age')} AND max_age >= #{options[:user].get('age')}"
    end
  end

  def self.default_search_options(o = {})
    options = {:statuses => ["live"]}

    return options if o[:user].blank?

    options[:statuses] << "testing" if o[:user].tester? || o[:user].admin?
    options
  end

  def self.demo_nav_bar
    calculator_navbar_count = Preference.get(:calculator_navbar_count).to_i
    search_params = {:statuses => Calculator::DEMO_STATUSES, :category_visible => true}
    Calculator.perform_search(search_params, :page => 1, :per_page => Calculator.count)
    .group_by {|calculator| calculator.category.try(:name)}
    .sort_by(&:first)
    .collect {|category_name, calculators| [category_name, calculators[0...calculator_navbar_count]]}
  end

  def self.nav_bar(options = {})
    calculator_navbar_count = Preference.get(:calculator_navbar_count).to_i
    search_params = Calculator.default_search_options(:user => options[:user])
    search_params[:nav_bar_eager_load] = true
    search_params[:category_visible] = true
    Calculator.perform_search(search_params, :page => 1, :per_page => Calculator.count)
    .group_by {|calculator| calculator.category.try(:name)}
    .sort_by(&:first)
    .collect {|category_name, calculators| [category_name, calculators[0...calculator_navbar_count]]}
  end

  def important_attributes
    super + [:interesting_facts, :dimensions, :upload, :attachments]
  end

  def can_sign_off?
    return true if self.status == 'final draft'
    return true if self.status == 'testing'
    false
  end

  def next_status
    {
      'testing' => 'live',
    }[self.status] || 'testing'
  end

  def comments_count
    self.comment_threads.real.count
  end

  def category_name=(new_name)
    return if new_name.blank?
    self.build_category if self.category.blank?
    self.category.name = new_name
  end

  def category_name
    self.category.try :name
  end

  def unvoted_poll(user)
    self.polls.eager_loaded.collect do |poll|
      poll unless poll.voted_by?(user)
    end.compact.first
  end

  def self.related_calculators(options = {})
    search_params = Calculator.default_search_options(:user => options[:user])
    search_params[:set_as_related_calcualtor] = true

    if options[:user].present?
      search_params[:gender] = ["any", options[:user].get("gender")] if options[:user].get("gender").present?
      search_params[:education] = ["any".to_crc32, options[:user].get("education_level").to_crc32] if options[:user].get("education_level").present?
      search_params[:without_submitter_user_ids] = [options[:user].id]
    end

    search_params[:limit] = 5
    search_params[:sphinx_select] = sphinx_select(options)
    search_params[:without_calculator_id] = options[:without_calculator_id]
    search_params[:carousel_eager_loaded] = options[:carousel_eager_loaded]

    Calculator.perform_search(search_params, :page => 1, :per_page => Calculator.count)
  end

  def self.demo
    ids = Preference.get(:demo_carousel_calculator_ids).split(',').collect(&:to_i)
    calculators = Calculator.where(:id => ids)
    ids.collect do |id|
      calculators.find {|calculator| calculator.id == id}
    end.compact
  end

  def self.of_carousel(user = nil)
    calculators = self.related_calculators(:user => user, :carousel_eager_loaded => true)
    carousel_calculators = self.real.show_in_carousel.carousel_eager_loaded
    if calculators.count < Preference.get("carousel_calculator_min_count").to_i
      return (calculators | carousel_calculators)[0..(Preference.get("carousel_calculator_max_count").to_i - 1)]
    end
    return calculators
  end

  def testing?
    self.status == 'testing'
  end

  def live?
    self.status == 'live'
  end

  def self.live_categories_with_count
    categories = {}
    self.includes([:category => :category_detail]).select {|c| c.category.try :visible?}.group_by{|c| c.category.try :name}.each do |c, v|
      categories[c.to_s] = v.count
    end

    categories
  end

  def missing_attributes
    a = super
    index = a.index('body')
    a[index] = 'sub_title' if index.present?
    a
  end

  def signoffs_remaining
    Preference.get(:calculator_signoffs_required).to_i - self.signoffs.length
  end

  def reset_signoffs
    return true unless self.status_changed?
    self.signoffs.each &:destroy
    self.signoffs.clear
  end

  def set_convenience_functions
    return unless self.sentence_changed?
    self.calculator_convenience_functions.each &:destroy
    self.calculator_convenience_functions.clear

    self.variables.each do |v|
      cf = ConvenienceFunction.find_by_name v
      if cf
        self.calculator_convenience_functions.build(:convenience_function_id => cf.id) unless self.calculator_convenience_functions.collect(&:convenience_function_id).include?(cf.id)
      end
    end
  end

  def signoff!(user_id)
    self.signoffs.create :user_id => user_id
  end

end
