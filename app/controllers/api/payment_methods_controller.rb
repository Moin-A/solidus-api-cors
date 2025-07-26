# frozen_string_literal: true

module Api
  class PaymentMethodsController < BaseController
    def index
      @payment_methods = Spree::PaymentMethod.available
      render json: @payment_methods.as_json
    end
  end
end 