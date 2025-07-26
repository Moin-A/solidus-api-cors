# frozen_string_literal: true

module Api
  class VariantsController < BaseController
    def index
      @variants = Spree::Variant.includes(:product, :option_values, :images)
                                .where(is_master: false)
                                .available
      render json: @variants.as_json(include: [:product, :option_values, :images])
    end

    def show
      @variant = Spree::Variant.includes(:product, :option_values, :images)
                               .find(params[:id])
      render json: @variant.as_json(include: [:product, :option_values, :images])
    end

    def by_product
      @variants = Spree::Variant.includes(:option_values, :images)
                                .where(product_id: params[:product_id])
                                .available
      render json: @variants.as_json(include: [:option_values, :images])
    end
  end
end 