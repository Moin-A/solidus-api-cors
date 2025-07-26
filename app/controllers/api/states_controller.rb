# frozen_string_literal: true

module Api
  class StatesController < BaseController
    def index
      @states = Spree::State.where(country_id: params[:country_id]).order(:name)
      render json: @states.as_json
    end
  end
end 