# frozen_string_literal: true

module Api
  class TestController < BaseController
    def index
      render json: { message: "API is working!", timestamp: Time.current }
    end
  end
end 