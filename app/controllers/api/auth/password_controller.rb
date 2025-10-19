module Api
  module Auth
    class PasswordController < Api::BaseController
        skip_before_action :authenticate_with_api_key

       def create           
            spree_user = Spree::User.find_by(email: user_params[:email])

            unless spree_user
                return render json: { error: I18n.t('devise.user_passwords.user_not_found') }, status: :not_found
            end

            spree_user.send_reset_password_instructions

            if spree_user.errors.any?
                render json: { errors: spree_user.errors.full_messages }, status: :unprocessable_entity
            else
                render json: { message: I18n.t('devise.user_passwords.send_instructions') }, status: :ok
            end
            
        end


        def update
            spree_user = Spree::User.reset_password_by_token(user_params)
             if spree_user.errors.any?
                render json: { errors: spree_user.errors.full_messages }, status: :unprocessable_entity
            else
                render json: { message: "Password has been reset successfully" }, status: :ok
            end
        end

        private

        def user_params
            user_params = params.require(:spree_user).permit(:email, :reset_password_token, :password, :password_confirmation)
        end    
     end
  end
end

