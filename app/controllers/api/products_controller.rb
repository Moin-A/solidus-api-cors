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

    def variants
      @product = Spree::Product.find(params[:id])
      @variants = @product.variants.includes(:option_values, :images).available
      render json: @variants.as_json(include: [:option_values, :images])
    end

    def related
      @product = Spree::Product.find(params[:id])
      @related_products = @product.taxons.flat_map(&:products)
                                 .reject { |p| p.id == @product.id }
                                 .uniq
                                 .first(4)
      render json: @related_products.as_json(include: [:variants, :taxons])
    end
  end
end 