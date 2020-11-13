class Api::V1::BudgetPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_budget, only: [:add_new_budget_group, :add_new_category_item, :edit_budget_group, :edit_category_item, :delete_budget_group, :delete_category_item]

  def create
    if params[:month].present? && params[:year].present?
      @budget = BudgetPlan.build_budget_for_new_month(current_user, Date::MONTHNAMES.index(params[:month]), params[:year])
    else
      @budget = BudgetPlan.build_default_budget(current_user)
    end

    if @budget.save
      render json: @budget, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.errors, status: :unprocessable_entity
    end
  end

  def add_new_budget_group
    @budget.add_new_budget_group

    if @budget.save
      render json: @budget, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.errors, status: :unprocessable_entity
    end
  end

  def add_new_category_item
    category_item = @budget.add_new_category_item(params[:category_id])

    if category_item.save
      render json: @budget.reload, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.reload.errors, status: :unprocessable_entity
    end
  end

  def edit_budget_group
    budget_category = @budget.budget_categories.find_by_id(params[:budget_category_id])

    if budget_category.present? && budget_category.update_attributes(budget_category_params)
      render json: @budget.reload, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.reload.errors, status: :unprocessable_entity
    end
  end

  def edit_category_item
    budget_category = @budget.budget_categories.find_by_id(params[:category_id])

    if budget_category.present?
      category_item = budget_category.category_items.find_by_id(params[:category_item_id])
      return render json: @budget.reload, include: [budget_categories: { include: [:category_items] }] unless category_item.present?
    end

    if budget_category.present? && category_item.present? && category_item.update_attributes(category_item_params)
      render json: @budget.reload, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.reload.errors, status: :unprocessable_entity
    end
  end

  def delete_budget_group
    budget_category = @budget.budget_categories.find(params[:budget_category_id]).destroy

    if budget_category.destroyed?
      render json: @budget.reload, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.reload.errors, status: :unprocessable_entity
    end
  end

  def delete_category_item
    budget_category = @budget.budget_categories.find(params[:category_id])
    category_item = budget_category.category_items.find(params[:category_item_id]).destroy

    if category_item.destroyed?
      render json: @budget.reload, include: [budget_categories: { include: [:category_items] }]
    else
      render json: @budget.reload.errors, status: :unprocessable_entity
    end
  end

  private
    def set_budget
      @budget = BudgetPlan.find(params[:budget_plan_id])
    end

    def budget_category_params
      params.require(:budget_category).permit(:name)
    end

    def category_item_params
      params.require(:category_item).permit(:name, :planned_amount)
    end
end

