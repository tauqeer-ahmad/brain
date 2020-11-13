class Api::V1::GroceriesController < Api::BaseController
  before_action :set_sort_param, only: :index
  before_action :set_grocery
  before_action :set_recipe, only: [:move_recipe_to_list, :mark_complete_by_recipe]
  before_action :set_meal_plan, only: :move_meal_plan_to_list

  include Concerns::Api::V1::Docs::GroceriesDoc

  param_group :doc_grocery_list
  def index
    ingredients = @grocery.search_grocery_items(@sort_param)
    paginated_ingredients = Kaminari.paginate_array(ingredients.to_a).page(params[:page]).per(params[:per_page])
    success_response(
      message: 'success',
      data: {
        records: ActiveModel::ArraySerializer.new(paginated_ingredients, each_serializer: sorted_serializer(@sort_param)),
        records_total: ingredients.count
      }
    )
  end

  param_group :doc_move_recipe_to_list
  def move_recipe_to_list
    @grocery.create_grocery_items(@recipe)
    success_response(message: 'success', data: [])
  end

  param_group :doc_mark_complete_by_recipe
  def mark_complete_by_recipe
    @grocery.mark_completed_by_recipe(@recipe.id)
    success_response(message: 'success', data: [])
  end

  param_group :doc_mark_complete_by_aisle
  def mark_complete_by_aisle
    @grocery.mark_completed_by_aisle(params[:aisle])
    success_response(message: 'success', data: [])
  end

  param_group :doc_clear_list
  def clear_list
    @grocery.grocery_items.destroy_all
    success_response(message: 'success', data: [])
  end

  param_group :doc_change_selected_states
  def change_selected_states
    @grocery.change_selected_states(params[:item_ids], params[:state])
    success_response(message: 'success', data: [])
  end

  param_group :doc_add_item
  def add_item
    @grocery.add_item(grocery_item_params)
    success_response(message: 'success', data: [])
  end

  param_group :doc_get_recipe_list
  def get_recipe_list
    recipes = @grocery.recipes.uniq
    success_response(message: 'success', data: ActiveModel::ArraySerializer.new(recipes, each_serializer: GroceryRecipeListSerializer))
  end

  param_group :doc_move_meal_plan_to_list
  def move_meal_plan_to_list
    message = @grocery.create_grocery_items_through_meal_plan(@meal_plan)
    success_response(message: message, data: [])
  end

  param_group :doc_details
  def details
    recipes = @grocery.recipes.uniq
    success_response(message: 'success', data: { recipes: ActiveModel::ArraySerializer.new(recipes, each_serializer: GroceryRecipeListSerializer), ingredients: ActiveModel::ArraySerializer.new(@grocery.grocery_items, each_serializer: GroceryItemSerializer) })
  end

  private

  def set_recipe
    @recipe = Recipe.includes(:recipe_ingredients).find(params[:recipe_id])
  end

  def grocery_item_params
    params.permit(:name, :quantity, :measurement, :recipe_id, :aisle)
  end

  def set_meal_plan
    @meal_plan = MealPlan.includes(recipes: :recipe_ingredients).find(params[:meal_plan_id])
  end

  def set_grocery
    @grocery = Grocery.includes(:grocery_items).find_or_create_by(user_id: current_user.id)
  end

  def set_sort_param
    @sort_param = params[:sort].to_s.downcase == 'aisle' && 'aisle' || 'recipe_id'
  end

  def sorted_serializer(sort_params)
    sort_params == 'aisle' ? GroceryAisleSerializer : GroceryRecipeSerializer
  end

end
