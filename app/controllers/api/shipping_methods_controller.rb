# frozen_string_literal: true

module Api
  class ShippingMethodsController < BaseController
    def index
      @shipping_methods = Spree::ShippingMethod.available
      render json: @shipping_methods.as_json
    end
  end
end 