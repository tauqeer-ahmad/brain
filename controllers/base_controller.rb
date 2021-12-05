class Admin::BaseController < ApplicationController

  before_filter :can_access!
  before_filter :check_admin_session

  protected

  def can_access?
    current_user.admin?
  end

  def session_access_expired?
    session[:admin] < Time.now.utc
  end

  def session_access_denied
    return unless Rails.env.production?
    redirect_to new_admin_session_path
  end

  def check_admin_session
    return session_access_denied if session[:admin].blank?
    return session_access_denied if session_access_expired?
    true
  end

  def can_access!
    unless user_signed_in?
      flash[:error] = get_message("error", "admin")
      return redirect_to root_path
    end
    unless can_access?
      flash[:error] = get_message("error", "admin")
      return redirect_to root_path
    end
  end
end
