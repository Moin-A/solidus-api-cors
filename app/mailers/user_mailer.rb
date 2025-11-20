class UserMailer < ApplicationMailer
  default from: ENV['DEFAULT_FROM_EMAIL'] || 'm0inahmedquintype@gmail.com'

  # Include URL helpers for email links
  include Rails.application.routes.url_helpers

  # Set default URL options
  def default_url_options
    Rails.application.config.action_mailer.default_url_options || { host: 'localhost', port: 3001 }
  end

  def welcome_email(user)
    @user = user
    mail(to: @user.email, subject: 'Welcome to Our App!')
  end

  def confirmation_email(user)
    @user = user
    mail(to: @user.email, subject: 'Please Confirm Your Email')
  end

  # Devise confirmation instructions
  def confirmation_instructions(record, token, _opts = {})
    @token = token
    @email = record.email
    @resource = record

    # Try to generate the confirmation URL, fallback to a simple URL if route doesn't exist
    begin
      @confirmation_url = user_confirmation_url(confirmation_token: @token)
    rescue StandardError
      # Fallback to a generic URL format
      host = default_url_options[:host]
      port = default_url_options[:port]
      base_url = port ? "#{host}:#{port}" : host
      @confirmation_url = "http://#{base_url}/api/verification/confirm_email?confirmation_token=#{@token}"
    end

    mail(to: record.email, subject: 'Confirm your email address')
  end

  # Devise reset password instructions
  def reset_password_instructions(record, token, opts = {})
    @token = token
    @resource = record
    
    # Generate password reset URL (don't pass record to avoid ID in URL)
    begin
      @reset_password_url = edit_password_url(reset_password_token: @token)
    rescue => e
      # Fallback to a generic URL format for API
      host = default_url_options[:host]
      port = default_url_options[:port]
      base_url = port ? "#{host}:#{port}" : host
      @reset_password_url = "http://#{base_url}/password/change?reset_password_token=#{@token}"
    end
    
    mail(to: record.email, subject: 'Reset your password')
  end

  # Devise unlock instructions (if using lockable)
  def unlock_instructions(record, token, _opts = {})
    @token = token
    @resource = record

    mail(to: record.email, subject: 'Unlock your account')
  end

  # Devise email changed notification
  def email_changed(record, _opts = {})
    @resource = record

    mail(to: record.email, subject: 'Email address changed')
  end

  # Devise password change notification
  def password_change(record, _opts = {})
    @resource = record

    mail(to: record.email, subject: 'Password changed')
  end
end
