class Api::V1::MealsController < Api::BaseController
  include Concerns::Api::V1::Docs::MealsDoc

  before_action :set_meal, only: [:like, :unlike, :save, :destroy, :update]
  before_action :authorize_user, only: [:destroy, :update]

  param_group :doc_get_feed
  def feed
    meals = current_user.get_feed.ordered.includes(:menu_items)
    paged_meals = meals.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_meals, meals.size, ENTITIES[:meal], current_user: current_user, current_user_tag_ids: current_user.tag_followees_ids))
  end

  param_group :doc_create_meal
  def create
    meal = Meals::UpdateMealService.new(current_user.meals.build, meal_params).call!
    two_zero_one(message: 'success', data: MealSerializer.new(meal, scope: { current_user: current_user }).as_json)
  end

  param_group :doc_update_meal
  def update
    Meals::UpdateMealService.new(@meal, meal_params).call!
    success_response(message: 'success', data: MealSerializer.new(@meal, scope: { current_user: current_user }).as_json)
  end

  param_group :doc_like_meal
  def like
    if @meal.like!(current_user.id)
      success_response(message: 'success', data: MealSerializer.new(@meal, scope: { current_user: current_user }).as_json)
    else
      four_twenty_two(message: error_message(@meal))
    end
  end

  param_group :doc_unlike_meal
  def unlike
    if @meal.unlike!(current_user.id)
      success_response(message: 'success', data: MealSerializer.new(@meal, scope: { current_user: current_user }).as_json)
    else
      four_twenty_two(message: error_message(@meal))
    end
  end

  param_group :doc_save_meal_to_recipe_box
  def save
    if @meal.save_to_recipe_box!(current_user)
      success_response(message: 'success')
    else
      four_twenty_two(message: error_message(@meal))
    end
  end

  param_group :doc_delete_meal
  def destroy
    if @meal.destroy
      success_response(message: 'success', data: {})
    else
      four_twenty_two(message: error_message(@meal))
    end
  end

  private

  def set_meal
    @meal = Meal.find(params[:id])
  end

  def authorize_user
    four_twenty_two(message: 'You are not authorized to perform this action!') unless @meal.owner?(current_user)
  end

  def meal_params
    params.require(:meal).permit(:caption, :tags, :picture,
      tagged_recipes: [:recipe_id, :x_cord, :y_cord, :x_cord_percent, :y_cord_percent],
      tagged_menu_items: [:name, :quantity, :measurement, :aisle, :x_cord_percent, :y_cord_percent])
  end
end
