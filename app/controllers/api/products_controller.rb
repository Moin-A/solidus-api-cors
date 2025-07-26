# frozen_string_literal: true

module Api
  class ProductsController < BaseController
    def index
      @products = Spree::Product.includes(:variants, :taxons).available
      render json: @products.as_json(include: [:variants, :taxons])
    end

    def show
      @product = Spree::Product.find(params[:id])
      render json: @product.as_json(include: [:variants, :taxons, :product_properties])
    end
  end
end 