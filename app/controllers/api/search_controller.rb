# frozen_string_literal: true

module Api
  class SearchController < BaseController
    def products
      query = params[:q]
      category_id = params[:category_id]
      min_price = params[:min_price] unless params[:price_range].blank?
      max_price = params[:max_price] unless params[:price_range].blank?
      page = params[:page] || 1
      key = params[:perma_link]
      min_price, max_price = params[:price_range].split(",").map(&:to_i) if params[:price_range].present?
      sort_by = params[:sort_by] || 'name'
      sort_order = params[:sort_order] || 'asc'
      # Apply price filter
      # binding.pry
      @products = Spree::Product.includes(:taxons, master: :images, variants: :images).where(spree_taxons: { permalink: params[:perma_link] }).available

      # Apply search query
      if query.present?
        @products = @products.where("spree_products.name ILIKE ? OR spree_products.description ILIKE ?", 
                                   "%#{query}%", "%#{query}%")
      end

      # Apply category filter
      if category_id.present?
        @products = @products.joins(:taxons).where(spree_taxons: { id: category_id })
      end


      # Apply price filter
      # binding.pry

      if min_price.present? || max_price.present?
        @products = @products.joins(master: :prices).where("spree_prices.amount >= ?", min_price) if min_price.present?
        @products = @products.joins(master: :prices).where("spree_prices.amount <= ?", max_price) if max_price.present?
      end

      # Apply sorting
      case sort_by
      when 'price'
        @products = @products.joins(:variants).order("spree_variants.price #{sort_order}")
      when 'created_at'
        @products = @products.order("spree_products.created_at #{sort_order}")
      else
        @products = @products.order("spree_products.name #{sort_order}")
      end

      # Pagination
      @products = @products.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        products: @products.as_json(include: 
          {
            taxons: {},            
            master:  {
                include: {
                  default_price: { only: [:amount, :currency] }
                }
              },

              images: { methods: [:attachment_url] }

          }
        ),
        pagination: {
          current_page: @products.current_page,
          total_pages: @products.total_pages,
          total_count: @products.total_count
        },
        filters: {
          query: query,
          category_id: category_id,
          min_price: min_price,
          max_price: max_price,
          sort_by: sort_by,
          sort_order: sort_order
        }
      }
    end

    def suggestions
      query = params[:q]
      return render json: { suggestions: [] } if query.blank?

      suggestions = []
      
      # Product name suggestions
      product_names = Spree::Product.where("name ILIKE ?", "%#{query}%")
                                   .limit(5)
                                   .pluck(:name)
      suggestions.concat(product_names)

      # Category suggestions
      category_names = Spree::Taxon.where("name ILIKE ?", "%#{query}%")
                                   .limit(5)
                                   .pluck(:name)
      suggestions.concat(category_names)

      render json: { suggestions: suggestions.uniq }
    end
  end
end 