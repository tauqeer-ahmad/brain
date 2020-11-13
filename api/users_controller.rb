class Api::V1::UsersController < Api::BaseController
  include Concerns::Api::V1::Docs::UsersDoc

  before_action :set_user, only: [:follow, :unfollow, :followers, :followees, :profile, :meals, :tags]
  before_action :validate_user, only: [:follow, :unfollow]

  param_group :doc_list_users
  def index
    users = User.search(params[:query])
    paged_users = users.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_users, users.size, ENTITIES[:user], current_user_followees_ids: current_user.user_followees_ids))
  end

  def update_info
    if current_user.update(user_params)
      success_response(message: 'success', data: UserSerializer.new(current_user).as_json)
    else
      four_twenty_two(message: error_message(current_user))
    end
  end

  param_group :doc_get_current_user_profile
  def my_profile
    success_response(message: 'success', data: UserSerializer.new(current_user).as_json)
  end

  param_group :doc_get_user_profile
  def profile
    success_response(message: 'success', data: UserSerializer.new(@user, scope: { current_user_followees_ids: current_user.user_followees_ids }).as_json)
  end

  param_group :doc_follow_user
  def follow
    if current_user.follow!(@user)
      current_user.reload
      success_response(message: 'success', data: UserSerializer.new(current_user).as_json)
    else
      four_twenty_two(message: 'You are already following this user')
    end
  end

  param_group :doc_unfollow_user
  def unfollow
    if current_user.unfollow!(@user)
      current_user.reload
      success_response(message: 'success', data: UserSerializer.new(current_user).as_json)
    else
      four_twenty_two(message: 'You are not following this user')
    end
  end

  param_group :doc_list_followers
  def followers
    followers = @user.user_followers
    paged_followers = followers.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_followers, followers.size, ENTITIES[:user], current_user_followees_ids: current_user.user_followees_ids))
  end

  param_group :doc_list_my_followers
  def my_followers
    followers = current_user.user_followers
    paged_followers = followers.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_followers, followers.size, ENTITIES[:user], current_user_followees_ids: current_user.user_followees_ids))
  end

  param_group :doc_list_followees
  def followees
    followees = @user.user_followees
    paged_followees = followees.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_followees, followees.size, ENTITIES[:user], current_user_followees_ids: current_user.user_followees_ids))
  end

  param_group :doc_list_my_followees
  def my_followees
    followees = current_user.user_followees
    current_user_followees_ids = followees.pluck(:id)
    paged_followees = followees.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_followees, followees.size, ENTITIES[:user], current_user_followees_ids: current_user_followees_ids))
  end

  param_group :doc_list_tags
  def tags
    tags = @user.tag_followees
    paged_tags = tags.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_tags, tags.size, ENTITIES[:tag], current_user_tag_ids: current_user.tag_followees_ids))
  end

  param_group :doc_list_my_tags
  def my_tags
    tags = current_user.tags(params[:query])
    current_user_tag_ids = tags.pluck(:id)
    paged_tags = tags.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_tags, tags.size, ENTITIES[:tag], current_user_tag_ids: current_user_tag_ids))
  end

  param_group :doc_list_meals
  def meals
    meals = @user.meals.ordered
    paged_meals = meals.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_meals, meals.size, ENTITIES[:meal], current_user: current_user, current_user_tag_ids: current_user.tag_followees_ids))
  end

  param_group :doc_list_my_meals
  def my_meals
    meals = current_user.meals.ordered
    paged_meals = meals.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_meals, meals.size, ENTITIES[:meal], current_user: current_user, current_user_tag_ids: current_user.tag_followees_ids))
  end

  param_group :doc_list_my_recipes
  def my_recipes
    recipes = current_user.recipes.non_rejected.ordered.includes(:interested_by, :user)
    paged_recipes = recipes.page(params[:page]).per(params[:per_page])

    success_response(get_list_response(paged_recipes, recipes.size, ENTITIES[:recipe]))
  end

  private

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :username, :location, :bio, :avatar)
  end

  def set_user
    @user = User.find(params[:id])
  end

  def validate_user
    four_twenty_two(message: 'Cannot follow/unfollow yourself') if @user == current_user
  end
end
