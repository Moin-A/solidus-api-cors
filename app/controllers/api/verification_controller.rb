# frozen_string_literal: true

module Api
  class VerificationController < BaseController
    skip_before_action :authenticate_with_api_key

    # POST /api/verification/confirm_email
    # Uses Devise confirmable
    def confirm_email
      user = Spree::User.confirm_by_token(params[:confirmation_token])

      if user.errors.empty?
        render json: {
          success: true,
          message: 'Email confirmed successfully',
          email_confirmed: true,
          phone_verified: user.phone_verified?,
          fully_verified: user.fully_verified?
        }, status: :ok
      else
        render json: {
          error: 'Invalid or expired confirmation token',
          details: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    # POST /api/verification/verify_phone
    def verify_phone
      user = Spree::User.find_by(phone_number: params[:phone_number])

      unless user
        render json: { error: 'User not found' }, status: :not_found
        return
      end

      if user.phone_verified?
        render json: { message: 'Phone already verified' }, status: :ok
        return
      end

      if user.verify_phone!(params[:token])
        render json: {
          success: true,
          message: 'Phone verified successfully',
          email_verified: user.email_verified?,
          phone_verified: true,
          fully_verified: user.fully_verified?
        }, status: :ok
      else
        render json: {
          error: 'Invalid or expired verification token'
        }, status: :unprocessable_entity
      end
    end

    # POST /api/verification/resend_confirmation
    # Uses Devise confirmable to resend confirmation email
    def resend_confirmation
      user = Spree::User.find_by(email: params[:email])

      unless user
        render json: { error: 'User not found' }, status: :not_found
        return
      end

      if user.confirmed?
        render json: { message: 'Email already confirmed' }, status: :ok
        return
      end

      # Devise handles resend automatically
      user.send_confirmation_instructions

      render json: {
        success: true,
        message: 'Confirmation email sent'
      }, status: :ok
    end

    # POST /api/verification/resend_phone
    def resend_phone
      user = Spree::User.find_by(phone_number: params[:phone_number])

      unless user
        render json: { error: 'User not found' }, status: :not_found
        return
      end

      if user.phone_verified?
        render json: { message: 'Phone already verified' }, status: :ok
        return
      end

      unless user.can_resend_phone_verification?
        render json: {
          error: 'Please wait before requesting another verification code',
          retry_after: 120 # seconds
        }, status: :too_many_requests
        return
      end

      user.send_phone_verification
      render json: {
        success: true,
        message: 'Verification code sent to your phone'
      }, status: :ok
    end
  end
end
