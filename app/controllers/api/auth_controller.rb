# frozen_string_literal: true

module Api
  class AuthController < BaseController
    def login
      user = Spree::User.find_by(email: params[:email])
      
      if user&.valid_password?(params[:password])
        render json: {
          success: true,
          user: {
            id: user.id,
            email: user.email,
            spree_api_key: user.spree_api_key
          },
          message: "Login successful"
        }
      else
        render json: {
          success: false,
          message: "Invalid email or password"
        }, status: :unauthorized
      end
    end

    def register
      user = Spree::User.new(
        email: params[:email],
        password: params[:password],
        password_confirmation: params[:password_confirmation]
      )

      if user.save
        render json: {
          success: true,
          user: {
            id: user.id,
            email: user.email,
            spree_api_key: user.spree_api_key
          },
          message: "Registration successful"
        }
      else
        render json: {
          success: false,
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    end
  end
end 