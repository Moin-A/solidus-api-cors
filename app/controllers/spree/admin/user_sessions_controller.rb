# frozen_string_literal: true

# Override the admin user sessions controller from solidus_auth_devise
# Based on: solidus_auth_devise/lib/controllers/backend/spree/admin/user_sessions_controller.rb
class Spree::Admin::UserSessionsController < Devise::SessionsController
  helper 'spree/base'

  include Spree::Core::ControllerHelpers::Auth
  include Spree::Core::ControllerHelpers::Common
  include Spree::Core::ControllerHelpers::Store

  helper 'spree/admin/navigation'
  layout 'spree/layouts/admin'

  # Completely disable CSRF protection for this controller
  # This is needed because the admin login form may not have a valid CSRF token
  # in production environments (e.g., when behind Traefik reverse proxy)
  skip_forgery_protection

  # Ensure we skip any authentication checks that might come from concerns
  # Skip authentication for the new action (login page) - users need to access it without being authenticated
  # Try to skip all possible authenticate_user methods
  skip_before_action :authenticate_user, only: [:new, :create], raise: false
  skip_before_action :load_user, only: [:new, :create], raise: false
  skip_before_action :load_user_roles, only: [:new, :create], raise: false
  # Devise's require_no_authentication redirects authenticated users away from login page
  # We want to allow access to the login page even if already authenticated (for logout/login scenarios)
  skip_before_action :require_no_authentication, only: [:new], raise: false
  
  # Override authenticate_user to do nothing for create action
  def authenticate_user
    Rails.logger.info "=== authenticate_user called for action: #{action_name} ==="
    # Do nothing - we handle authentication manually in create action
    if action_name == 'create' || action_name == 'new'
      Rails.logger.info "Skipping authenticate_user for #{action_name} action"
      return
    end
    # Call the original method for other actions
    Rails.logger.info "Calling super for authenticate_user"
    super if defined?(super)
  end

  # Override verify_authenticity_token to do nothing
  def create
    Rails.logger.info "=== LOGIN CREATE DEBUG START ==="
    Rails.logger.info "Method create called!"
    Rails.logger.info "Request referer: #{request.referer.inspect}"
    Rails.logger.info "Request referer nil?: #{request.referer.nil?}"
    Rails.logger.info "Params: #{params[:spree_user].inspect}"
    Rails.logger.info "Params permitted?: #{params[:spree_user].respond_to?(:permitted?) ? params[:spree_user].permitted? : 'N/A'}"
    Rails.logger.info "sign_in_params: #{sign_in_params.inspect}"
    Rails.logger.info "Skipping spree_user_signed_in? check - it might trigger authentication"
    # Skip spree_user_signed_in? as it might trigger authentication checks
    # We'll check authentication manually below
    Rails.logger.info "About to start manual authentication..."
    begin
      auth_opts = auth_options
      Rails.logger.info "auth_options returned: #{auth_opts.inspect}"
    rescue => e
      Rails.logger.error "auth_options raised exception: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
    Rails.logger.info "Before actions that should run: #{_process_action_callbacks.select { |c| c.kind == :before }.map(&:filter).inspect}"
    Rails.logger.info "About to start manual authentication..."
    Rails.logger.info "FLUSHING LOGS BEFORE AUTHENTICATION"
    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    
    # Use Devise's standard authentication flow
    # Build resource from params and authenticate
    # Try to authenticate with the permitted params
    Rails.logger.info "Attempting authentication with email: #{sign_in_params[:email]}"
    Rails.logger.info "sign_in_params keys: #{sign_in_params.keys.inspect}"
    
    # Manually authenticate using the permitted params
    user = Spree::User.find_by(email: sign_in_params[:email])
    Rails.logger.info "User lookup result: #{user.inspect}"
    
    if user && user.valid_password?(sign_in_params[:password])
      Rails.logger.info "Password is valid, signing in user"
      self.resource = user
      set_flash_message!(:notice, :signed_in)
      Rails.logger.info "About to call sign_in..."
      begin
        sign_in(resource_name, resource)
        Rails.logger.info "sign_in completed successfully"
      rescue => e
        Rails.logger.error "sign_in raised exception: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        raise
      end
      # Don't call spree_current_user here as it might trigger warden.authenticate
      # Use the resource (user) we already have instead
      Rails.logger.info "User signed in successfully - resource: #{resource.inspect}"
      Rails.logger.info "About to build redirect path..."
      # Use resource instead of spree_current_user to avoid triggering authentication
      redirect_path = after_sign_in_path_for(resource)
      Rails.logger.info "Redirect path: #{redirect_path.inspect}"
      Rails.logger.info "Proceeding with redirect"
      Rails.logger.flush if Rails.logger.respond_to?(:flush)
      respond_to do |format|
        format.html {
          flash[:success] = I18n.t('spree.logged_in_succesfully')
          redirect_back_or_default(redirect_path)
          return # Explicitly return after redirect
        }
        format.js {
          user = resource.record
          render json: { ship_address: user.ship_address, bill_address: user.bill_address }.to_json
          return # Explicitly return after render
        }
      end
    else
      Rails.logger.error "Authentication failed"
      Rails.logger.error "User found?: #{user.present?}"
      Rails.logger.error "Password valid?: #{user&.valid_password?(sign_in_params[:password])}"
      Rails.logger.error "Password provided: #{sign_in_params[:password].inspect}"
      Rails.logger.error "User email: #{user&.email}"
      Rails.logger.error "User has encrypted_password?: #{user&.encrypted_password.present?}"
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      flash.now[:error] = t('devise.failure.invalid')
      render :new
      Rails.logger.info "=== END LOGIN CREATE DEBUG (AUTH FAILED) ==="
      return
    end
    Rails.logger.info "=== END LOGIN CREATE DEBUG ==="
  end

  def authorization_failure
  end

  protected

  # Override Devise's after_sign_in_path_for to redirect admin users to /admin
  def after_sign_in_path_for(resource)
    # Use signed_in_root_path which returns /admin
    signed_in_root_path(resource)
  end

  # Override sign_in_params to ensure params are permitted
  def sign_in_params
    Rails.logger.info "sign_in_params called - params[:spree_user]: #{params[:spree_user].inspect}"
    # Handle case when params are not present (e.g., on new action)
    return {} unless params[:spree_user].present?
    permitted = params.require(:spree_user).permit(:email, :password, :remember_me)
    Rails.logger.info "sign_in_params permitted: #{permitted.inspect}"
    permitted
  end

  private

  def signed_in_root_path(_resource)
    # Use Spree::Core::Engine routes to get admin path
    # This works in both development and production
    Rails.logger.info "signed_in_root_path called for resource: #{_resource.inspect}"
    begin
      path = Spree::Core::Engine.routes.url_helpers.admin_path
      Rails.logger.info "signed_in_root_path resolved to: #{path.inspect}"
      path
    rescue => e
      Rails.logger.error "signed_in_root_path failed: #{e.class} - #{e.message}"
      # Fallback to direct path if route helper fails
      '/admin'
    end
  end

  # NOTE: as soon as this gem stops supporting Solidus 3.1 if-else should be removed and left only include
  if defined?(::Spree::Admin::SetsUserLanguageLocaleKey)
    include ::Spree::Admin::SetsUserLanguageLocaleKey
  else
    def set_user_language_locale_key
      :admin_locale
    end
  end

  def accurate_title
    I18n.t('spree.login')
  end

  def redirect_back_or_default(default)
    # Use absolute URL to prevent Traefik from modifying the Location header
    # Traefik may rewrite relative URLs incorrectly, so we send absolute URLs
    
    # Debug logging to understand redirect behavior
    Rails.logger.info "=== REDIRECT DEBUG ==="
    Rails.logger.info "default parameter: #{default.inspect}"
    Rails.logger.info "session['spree_user_return_to']: #{session['spree_user_return_to'].inspect}"
    Rails.logger.info "request.protocol: #{request.protocol.inspect}"
    Rails.logger.info "request.host_with_port: #{request.host_with_port.inspect}"
    Rails.logger.info "request.referer: #{request.referer.inspect}"
    
    # Always use the default path for admin login - don't rely on referer or session
    # This prevents redirects to unauthorized_path when HTTP_REFERER is missing
    redirect_path = default
    Rails.logger.info "redirect_path (using default): #{redirect_path.inspect}"
    
    redirect_url = if redirect_path.start_with?('http://', 'https://')
      Rails.logger.info "redirect_path is already absolute: #{redirect_path.inspect}"
      redirect_path
    else
      # Build absolute URL using the request's protocol and host
      built_url = "#{request.protocol}#{request.host_with_port}#{redirect_path}"
      Rails.logger.info "built redirect_url: #{built_url.inspect}"
      built_url
    end
    
    Rails.logger.info "FINAL redirect_url: #{redirect_url.inspect}"
    Rails.logger.info "=== END REDIRECT DEBUG ==="
    
    redirect_to redirect_url
    session["spree_user_return_to"] = nil
  end
end
