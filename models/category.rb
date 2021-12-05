class Category < ActiveRecord::Base
  include Archiveable

  attr_accessible :categorical_id, :categorical_type, :name

  after_create :update_category_detail

  validates_presence_of :name

  belongs_to :categorical, :polymorphic => true

  belongs_to :category_detail, :foreign_key => "name", :primary_key => "name"

  scope :unique, :select => "DISTINCT(categories.name) as name"
  scope :visible, :joins => :category_detail, :conditions => ["category_details.visible = ?", true]
  scope :unique_type, :select => "DISTINCT(categorical_type) as categorical_type"
  scope :ordered, :order => "name ASC"
  scope :calculators, :conditions => {:categorical_type => "Calculator"}
  scope :libraries, :conditions => {:categorical_type => "Library"}
  scope :posts, :conditions => {:categorical_type => "Post"}
  scope :polls, :conditions => {:categorical_type => "Poll"}
  scope :videos, :conditions => {:categorical_type => "Video"}
  scope :uploads, :conditions => {:categorical_type => "Upload"}
  scope :preferences, :conditions => {:categorical_type => "Preference"}
  scope :helps, :conditions => {:categorical_type => "Help"}
  scope :emails, :conditions => {:categorical_type => "Email"}
  scope :pages, :conditions => {:categorical_type => "Page"}
  scope :convenience_functions, :conditions => {:categorical_type => "ConvenienceFunction"}
  scope :messages, :conditions => {:categorical_type => "Message"}
  scope :quotes, :conditions => {:categorical_type => "Quote"}
  scope :interesting_facts, :conditions => {:categorical_type => "InterestingFact"}
  scope :eager_loaded, :include => [:categorical]
  scope :eager_loaded_with_category_detail, :include => [:category_detail]

  def update_category_detail
    category_detail = CategoryDetail.find_by_name self.name
    return category_detail if category_detail

    category_detail = CategoryDetail.new :name => self.name, :color => "FFFFFF"
    category_detail.save
  end

  def color
    self.category_detail.try(:color) || "FFFFFF"
  end

  def visible?
    self.category_detail.try :visible?
  end

end
