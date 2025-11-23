# app/controllers/api/stores_controller.rb
class Api::StoresController < ApplicationController
    def show
      @store = Spree::Store.find(params[:id])
      
      render json: @store.as_json.merge(
        hero_image_url: @store.hero_image.attached? ? @store.hero_image.url : nil
      )
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Store not found' }, status: :not_found
    end
  end