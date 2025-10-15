# frozen_string_literal: true

module Api
  class AuthController < BaseController
    skip_before_action :authenticate_with_api_key, only: [:login, :register]

    def login
      user = Spree::User.find_by(email: params[:email])
      
      if user&.valid_password?(params[:password])
        # Generate API key if it doesn't exist
        user.generate_spree_api_key! unless user.spree_api_key
        
        # Assign customer role if user has no roles
        if user.spree_roles.empty?
          customer_role = Spree::Role.find_by(name: 'customer')
          user.spree_roles << customer_role if customer_role
        end
        # Set spree_api_key in a secure, HTTP-only cookie
        cookies.encrypted[:spree_api_key] = {
          value: user.spree_api_key,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
        render json: {
          success: true,
          user: {
            id: user.id,
            email: user.email
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
        # Generate API key if it doesn't exist
        user.generate_spree_api_key! unless user.spree_api_key
        
        # Assign customer role
        customer_role = Spree::Role.find_by(name: 'customer')
        user.spree_roles << customer_role if customer_role && !user.spree_roles.include?(customer_role)
        
        cookies.encrypted[:spree_api_key] = {
          value: user.spree_api_key,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
        render json: {
          success: true,
          user: {
            id: user.id,
            email: user.email
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

    def logout
      if current_user
        current_user.generate_spree_api_key!
        current_user.save
      end
      cookies.delete(:spree_api_key)
      render json: { success: true, message: "Logged out" }
    end
  end
end 