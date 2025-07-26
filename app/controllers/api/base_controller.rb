# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_with_api_key

    private

    def authenticate_with_api_key
      api_key = cookies.encrypted[:spree_api_key]

      @current_user = Spree::User.find_by(spree_api_key: api_key)
      unless @current_user
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    def current_user
      @current_user
    end
  end
end 