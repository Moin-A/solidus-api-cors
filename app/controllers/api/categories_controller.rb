# frozen_string_literal: true

module Api
  class CategoriesController < BaseController
    def index
      @categories = Spree::Taxon.includes(:children, :products)
                                .where(parent_id: nil)
                                .order(:id)
      render json: @categories.as_json(include: [:children, :products])
    end

    def show
      @category = Spree::Taxon.includes(:children, :products, :parent)
                              .find(params[:id])
      render json: @category.as_json(include: [:children, :products, :parent])
    end

    def taxons
      @category = Spree::Taxon.find_by(permalink: "categories/#{params[:id]}")
      if @category.nil?
        render json: {error: "Category notFound"}, status: :not_found
      else
        render json: @category.as_json.merge(
          attachment_url: @category.attachment_url
        )
      end
    end

    def products
      @category = Spree::Taxon.find(params[:id])
      @products = @category.products.includes(:variants, :taxons)
                          .available
                          .page(params[:page])
                          .per(params[:per_page] || 20)
      render json: {
        category: @category.as_json,
        products: @products.as_json(include: [:variants, :taxons]),
        pagination: {
          current_page: @products.current_page,
          total_pages: @products.total_pages,
          total_count: @products.total_count
        }
      }
    end
  end
end 