# frozen_string_literal: true

module Api
  class CountriesController < BaseController
    def index
      @countries = Spree::Country.includes(:states).order(:name)
      render json: @countries.as_json(include: [:states])
    end
  end
end 