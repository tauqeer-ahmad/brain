class Api::BaseController < ActionController::API
  before_action :require_login
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Concerns::ExceptionHandler
  include Concerns::ResponseHandler

  resource_description do
    api_version 'v1'
    api_base_url '/api'
  end

  def authenticate_token(user)
    token = TokenIssuer.build.find_token(user, auth_token_from_headers)
    if token
      touch_token(token)
      return true
    end
    false
  end

  def error_message(object = {})
    return object.errors.full_messages.first if object.present? && object.errors.present?
    "something went wrong"
  end

  def authenticate_user
    User.find_by(email: user_email_from_headers)
  end

  def user_email_from_headers
    request.headers["HTTP_X_USER_EMAIL"]
  end

  def auth_token_from_headers
    request.headers["HTTP_X_AUTH_TOKEN"]
  end

  def current_user
    user = authenticate_user
    return unauthorized_request(message: "Authentication failed for user/token") if user.blank?
    return unauthorized_request(message: "Authentication failed for user/token") unless authenticate_token(user)
    @current_user ||= user
  end

  def touch_token(token)
    token.update_attribute(:last_used_at, DateTime.current) if token.last_used_at < 1.hour.ago
  end

  def require_login
    user = authenticate_user
    (user && authenticate_token(user)) || unauthorized_request(message: "Unauthorized access")
  end
end
