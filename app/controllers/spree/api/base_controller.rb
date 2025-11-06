# frozen_string_literal: true

require 'spree/api/responders'

module Spree
  module Api
    # Override the gem's BaseController to inherit from ApplicationController
    class BaseController < ApplicationController
      self.responder = Spree::Api::Responders::AppResponder
      respond_to :json
      protect_from_forgery unless: -> { request.format.json? }

      include CanCan::ControllerAdditions
      include ActiveStorage::SetCurrent
      include Spree::Core::ControllerHelpers::Store
      include Spree::Core::ControllerHelpers::Pricing
      include Spree::Core::ControllerHelpers::StrongParameters

      class_attribute :admin_line_item_attributes
      self.admin_line_item_attributes = [:price, :variant_id, :sku]

      class_attribute :admin_metadata_attributes
      self.admin_metadata_attributes = [{ admin_metadata: {} }]

      attr_accessor :current_api_user

      before_action :load_user
      before_action :authorize_for_order, if: proc { order_token.present? }
      before_action :authenticate_user
      before_action :load_user_roles

      rescue_from ActionController::ParameterMissing, with: :parameter_missing_error
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from CanCan::AccessDenied, with: :unauthorized
      rescue_from Spree::Core::GatewayError, with: :gateway_error
      rescue_from StateMachines::InvalidTransition, with: :invalid_transition

      helper Spree::Api::ApiHelpers


      def load_order
        if order_id == 'current'|| order_id.nil?
          # Get or create the current user's active cart
          @order = current_api_user.orders.incomplete.last || 
                  Spree::Order.create!(
                    user: current_api_user,
                    store: Spree::Store.default
                  )
        else
          @order = Spree::Order.includes(:line_items).find_by!(number: order_id)
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Order not found' }, status: :not_found
      end

      private

      def set_current_store
        @current_store ||= Spree::Store.current(request.env['SERVER_NAME'])
      end

      def load_user
        @current_api_user ||= Spree.user_class.find_by(spree_api_key: api_key.to_s)
        
        # Fall back to warden session for admin dashboard AJAX requests
        if @current_api_user.nil? && respond_to?(:warden, true) && warden.authenticated?(:spree_user)
          @current_api_user = warden.user(:spree_user)
        end
      end

      def authenticate_user
        unless @current_api_user
          render json: { error: 'You must specify an API key.' }, status: :unauthorized
        end
      end

      def load_user_roles
        @current_user_roles = @current_api_user ? @current_api_user.spree_roles.pluck(:name) : []
      end

      def current_user
        @current_api_user
      end

      def unauthorized
        render json: { error: 'You are not authorized to perform that action.' }, status: :unauthorized
      end

      def gateway_error(exception)
        @order.errors.add(:base, exception.message)
        invalid_resource!(@order)
      end

      def invalid_transition(exception)
        @order.errors.add(:base, exception.message)
        invalid_resource!(@order)
      end

      def api_key
        # Check Authorization Bearer header first (standard OAuth format)
        bearer_token = request.headers['Authorization']&.match(/Bearer (.+)/)&.[](1)
        
        # Fall back to other methods
        bearer_token || 
          request.headers['X-Spree-Token'] || 
          params[:token] || 
          cookies.encrypted[:spree_api_key]
      end

      alias :order_token :api_key

      def not_found
        render json: { error: 'The resource you were looking for could not be found.' }, status: :not_found
      end

      def parameter_missing_error(exception)
        render json: { error: exception.message }, status: :unprocessable_entity
      end

      def invalid_resource!(resource)
        @resource = resource
        render json: { errors: @resource.errors.full_messages }, status: :unprocessable_entity
      end

      def authorize_for_order
        # Skip for 'current' order - let individual controllers handle it
        return if order_id == 'current'
        
        @order = Spree::Order.find_by(number: order_id) || Spree::Order.find_by(id: order_id)
        authorize! :show, @order, order_token if @order
      end

      def order_id
        params[:order_id] || params[:checkout_id] || params[:order_number]
      end

      def current_ability
        Spree::Ability.new(current_api_user)
      end

      def invalid_api_key
        render json: { error: 'Invalid API key' }, status: :unauthorized
      end

      # Pagination helper for Kaminari
      def paginate(resource)
        resource.page(params[:page]).per(params[:per_page] || default_per_page)
      end

      def default_per_page
        Kaminari.config.default_per_page
      end

      # Lock order to prevent concurrent modifications
      def lock_order
        Spree::OrderMutex.with_lock!(@order) { yield }
      rescue Spree::OrderMutex::LockFailed => error
        render plain: error.message, status: :conflict
      end

      # Handle insufficient stock errors
      def insufficient_stock_error(exception)
        logger.error "insufficient_stock_error #{exception.inspect}"
        render(
          json: {
            errors: [I18n.t(:quantity_is_not_available, scope: "spree.api.order")],
            type: 'insufficient_stock'
          },
          status: :unprocessable_entity
        )
      end
    end
  end
end

