class Api::V1::Devise::SessionsController < Api::BaseController
  skip_before_action :require_login, only: [:create, :existing_user, :social_login]
  def create
    resource = User.find_for_database_authentication(email: session_params[:email])

    if resource && resource.valid_password?(session_params[:password])
      if resource.confirmed?
        resource.transaction do
          resource.increment!(:sign_in_count)
          token = TokenIssuer.create_and_return_token(resource, request)

          success_response(message: 'success', data: LoginSerializer.new(resource, scope: { token: token }).as_json)
        end
      else
        four_zero_one(message: "You have to confirm your email address before continuing", resend_confirmation_email_link: new_user_confirmation_url)
      end
    else
      four_zero_one(message: "Error with your login or password")
    end
  end

  def social_login
    resource = User.social_login(social_login_params, social_auth_params)
    resource.increment(:sign_in_count)

    if resource.save(validate: false)
      resource.attach_image(params[:avatar_url]) if params[:avatar_url].present?
      token = TokenIssuer.create_and_return_token(resource, request)
      return success_response(message: 'success', data:  LoginSerializer.new(resource, scope: {token: token}).as_json)
    else
      return four_zero_one(message: "Error with your login or password")
    end
  end

  def destroy
    TokenIssuer.expire_token(current_user, request) if current_user
    success_response(message: "success")
  end

  private

  def session_params
    params.permit(:email, :password)
  end

  def social_login_params
    params.require(:user).permit(:email, :first_name, :last_name)
  end

  def social_auth_params
    params.require(:auth).permit(:uid, :provider)
  end
end
