class Recipe < ApplicationRecord
  include PgSearch

  TIME_SCALES = %w(minutes hours)
  INTERNAL_SOURCE = 'internal'
  EXTERNAL_SOURCE = 'external'
  UNAPPROVED_STATUS = 'unapproved'
  APPROVED_STATUS = 'approved'
  REJECTED_STATUS = 'rejected'
  DIMENSIONS = { thumbnail: '130x130', original: '2000x1350', medium: '350x350' }

  acts_as_taggable_on :tags

  validates :source, inclusion: { in: [INTERNAL_SOURCE, EXTERNAL_SOURCE] }
  validates :name, presence: { message: "Recipe name can't be blank" }
  validates :user_id, presence: { message: "Recipe user can't be blank" }
  validates :prep_time, presence: true, numericality: { greater_than: 0 }
  validates :active_time, presence: true, numericality: { greater_than: 0 }
  validates :number_of_servings, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :number_of_calories, numericality: { greater_than: 0 }, allow_nil: true
  validates :external_url, presence: true, if: :external_recipe?
  validates :recipe_ingredients, presence: true
  validates :directions, presence: true, unless: :external_recipe?
  validates :description, length: { maximum: 150 }
  validates :created_by, presence: true, length: { maximum: 128 }
  validate  :picture, :validate_picture

  include AASM
  aasm(:status) do
    state :unapproved, initial: true
    state :approved
    state :rejected
    state :uploaded

    event :approve do
      transitions to: :approved
    end

    event :unapprove do
      transitions to: :unapproved
    end

    event :reject do
      transitions to: :rejected
    end

    event :upload do
      transitions to: :uploaded
    end
  end

  has_one_attached :picture

  has_many :recipe_ingredients, inverse_of: :recipe, dependent: :destroy
  has_many :ingredients, through: :recipe_ingredients
  has_many :directions, inverse_of: :recipe, dependent: :destroy
  has_many :recipe_categories, inverse_of: :recipe, dependent: :destroy
  has_many :categories, through: :recipe_categories
  has_many :meal_recipes, dependent: :destroy
  has_many :meals, through: :meal_recipes
  has_many :meal_plan_recipes, dependent: :destroy
  has_many :meal_plans, through: :meal_plan_recipes
  has_many :interested_recipes, inverse_of: :recipe, dependent: :destroy
  has_many :interested_by, through: :interested_recipes, source: :user
  has_many :grocery_items, dependent: :destroy
  has_many :groceries, through: :grocery_items

  belongs_to :user

  accepts_nested_attributes_for :recipe_ingredients, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :directions, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :recipe_categories,
                                reject_if: :all_blank,
                                allow_destroy: true

  multisearchable against: [:name], if: lambda { |recipe| recipe.non_rejected? }
  pg_search_scope :filter_by_name, against: :name, using: { tsearch: { prefix: true } }

  scope :meal_posts, -> { where(meal_post: true) }
  scope :ordered, -> { order('updated_at desc') }
  scope :filter_by_user_ids, -> (user_ids) { where(user_id: user_ids) }
  scope :non_rejected, -> { where.not(status: REJECTED_STATUS) }
  scope :with_ids, -> (ids) { where(id: ids) }
  scope :non_deletable, -> { where(deletable: false) }
  scope :order_by_interested_count, -> { left_joins(:interested_recipes).group(:id).order('count(interested_recipes.id) DESC') }

  before_save :update_complete!

  paginates_per RECORDS_PER_PAGE

  def external_recipe?
    self.source == EXTERNAL_SOURCE
  end

  def non_rejected?
    self.status != REJECTED_STATUS
  end

  def display_picture(type = :original)
    return 'placeholder-img.png' unless picture.attached?
    style = picture_style(type)
    picture.variant(style)
    rescue
      picture.attachment.destroy
      'placeholder-img.png'
  end

  def posted_by
    user.username
  end

  def creator_name
    created_by || (new_record? && user && posted_by || '')
  end

  def category_names
    categories.pluck(:name).join(' ')
  end

  def creator_image
    posted_by == created_by &&  user.display_avatar || 'created-by-default-img.png'
  end

  def self.explore_recipes(name)
    return order_by_interested_count.non_rejected if name.blank?
    recipe_ids = filter_by_name(name).ids
    category_ids = Category.filter_by_name(name).ids
    recipe_ids += RecipeCategory.get_recipe_ids(category_ids)
    Recipe.non_rejected.with_ids(recipe_ids.uniq)
  end

  def self.explore_followees_recipes(user, name)
    recipe_ids = Recipe.filter_by_user_ids(user.user_followees_ids).filter_by_name(name).ids
    category_ids = user.categories.filter_by_name(name).ids
    recipe_ids += RecipeCategory.get_recipe_ids(category_ids)
    Recipe.non_rejected.with_ids(recipe_ids.uniq)
  end

  def self.search_recipes(options = {},user)
    case options[:type]
    when InterestedRecipe::STATUS[:saved]
      user.saved_recipes
    when InterestedRecipe::STATUS[:goto]
      user.goto_recipes
    else
      options[:query].present? ? non_rejected.filter_by_name(options[:query]) : non_rejected
    end
  end

  def self.user_recipes(user_id)
    filter_by_user_ids(user_id).non_rejected
  end

  def self.search_admin_recipes(name)
    name.presence && filter_by_name(name).ordered || ordered
  end

  def format_ingredients_params
    recipe_ingredients.ordered.includes(:ingredient).collect do |recipe_ingredient|
      recipe_ingredient.as_json(only: [:name, :quantity, :measurement, :preparation, :recipe_id]).merge('aisle' => recipe_ingredient.aisle)
    end
  end

  private

  def update_complete!
    self.complete = valid?
  end

  def picture_style(style)
    case style
    when :medium
      { resize: DIMENSIONS[style] }
    else
      { combine_options: { thumbnail: "#{DIMENSIONS[style]}^", gravity: 'center', extent: DIMENSIONS[style] } }
    end
  end  

  def validate_picture
    if picture.attached? && !picture.attachment.blob.content_type.in?(Constants::VALID_IMAGE_TYPES)
        errors.add(:picture, 'Must be an image file.')
        false
    end
  end
end
