# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_with_api_key, unless: :skip_authentication?
    before_action :set_active_storage_current

    private

    def authenticate_with_api_key
      api_key = cookies.encrypted[:spree_api_key]

      @current_user = Spree::User.find_by(spree_api_key: api_key)
      unless @current_user
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
    
    def skip_authentication?
      public_url = [
        "api/products#index",
        "api/products#show"
      ]
     
      public_url.include?"#{params["controller"]}##{params["action"]}"
    end  

    def current_user
      @current_user
    end

    def set_active_storage_current
      ActiveStorage::Current.url_options = {
        host: request.host_with_port,
        protocol: request.protocol
      }
    end
  end
end 