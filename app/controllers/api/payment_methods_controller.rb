# frozen_string_literal: true

module Api
  class PaymentMethodsController < BaseController
    def index
      @payment_methods = Spree::PaymentMethod.active.available_to_users
      render json: @payment_methods.as_json
    end
  end
end 