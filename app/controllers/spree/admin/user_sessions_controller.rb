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
  skip_before_action :authenticate_user, only: [:new, :create], raise: false
  skip_before_action :load_user, only: [:new, :create], raise: false
  skip_before_action :load_user_roles, only: [:new, :create], raise: false
  # Devise's require_no_authentication redirects authenticated users away from login page
  # We want to allow access to the login page even if already authenticated (for logout/login scenarios)
  skip_before_action :require_no_authentication, only: [:new], raise: false

  # Override verify_authenticity_token to do nothing
  def create
    # Use Devise's standard authentication flow
    # authenticate_spree_user! authenticates and signs in the user
    authenticate_spree_user!

    if spree_user_signed_in?
      respond_to do |format|
        format.html {
          flash[:success] = I18n.t('spree.logged_in_succesfully')
          redirect_back_or_default(after_sign_in_path_for(spree_current_user))
        }
        format.js {
          user = resource.record
          render json: { ship_address: user.ship_address, bill_address: user.bill_address }.to_json
        }
      end
    else
      flash.now[:error] = t('devise.failure.invalid')
      render :new
    end
  end

  def authorization_failure
  end

  protected

  # Override Devise's after_sign_in_path_for to redirect admin users to /admin
  def after_sign_in_path_for(resource)
    # Use signed_in_root_path which returns /admin
    signed_in_root_path(resource)
  end

  private

  def signed_in_root_path(_resource)
    # Use Spree::Core::Engine routes to get admin path
    # This works in both development and production
    Spree::Core::Engine.routes.url_helpers.admin_path
  rescue
    # Fallback to direct path if route helper fails
    '/admin'
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
    redirect_path = session["spree_user_return_to"] || default
    redirect_url = if redirect_path.start_with?('http://', 'https://')
      redirect_path
    else
      # Build absolute URL using the request's protocol and host
      "#{request.protocol}#{request.host_with_port}#{redirect_path}"
    end
    redirect_to redirect_url
    session["spree_user_return_to"] = nil
  end
end
