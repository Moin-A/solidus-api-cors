# frozen_string_literal: true

module Api
  class ProductsController < BaseController
    def index
      page = params[:page] || 1
      key = params[:taxon_id] || params[:perma_link]
        cache_key = "products_index_taxon_#{key}_page_#{page}_per_#{page}"
        @products = Rails.cache.fetch(cache_key, expires_in: 1.hour) do 
          if params[:taxon_id]
            Spree::Product.includes(:taxons, master: :images, variants: :images)
                          .where(spree_taxons: {id: params[:taxon_id]})
                          .available
          else  
            Spree::Product.includes(:taxons, master: :images, variants: :images)
                          .where(spree_taxons: { permalink: params[:perma_link] })
                          .available
          end  
        end

        @products = paginate(@products)    

        render json: {
          products: @products.as_json(
            include: {             
              taxons:  {},
              master:  {
                include: {
                  default_price: { only: [:amount, :currency] }
                }
              },
              images:  { methods: [:attachment_url] }
            }
          ),
          pagination: {
            current_page: @products.current_page,
            total_pages:  @products.total_pages,
            total_count:  @products.total_count
          }
        }
      end

    def show
      
      cache_key = "products_show_product_id_#{params[:id]}"

      @product_json = Rails.cache.fetch(cache_key, expires_in: 1.hour) do 
        @product = Spree::Product.friendly.find(params[:id])
        product_json = @product.as_json(
          include: {
            variants_including_master: {
              include: 
              { 
                images: { 
                only: [:alt] ,
                methods: [:url]
                },
                option_values: {
                  include: {
                    option_type: {
                      only: [:name]  # or [:id, :name, :presentation] if you want more
                    }
                  }
                } 
              }
            },
            taxons: {},
            product_properties: {
              only: [:value],
              include: { property: { only: [:name] } }
            },
            primary_taxon: {},
            images: {},
            master: {},
          }
        ) 
  
          option_values = Spree::OptionValue.grouped_by_option_type_with_ids(@product.variant_option_value_ids)
  
  
          product_json['option_types'] = grouped_option_types_with_values(option_values)
  
  
          product_json['images'] = @product.images.map do |image|
            {
              id: image.id,
              alt: image.alt,
              url: image.attachment.attached? ? url_for(image.attachment) : nil,
              thumb_url: image.attachment.attached? ? url_for(image.attachment.variant(resize_to_limit: [200, 200])) : nil
            }
          end
          product_json 
      end 
      
      render json: @product_json
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

    private

    def grouped_option_types_with_values(option_values)
      option_values.group_by(&:option_type).map do |option_type, values|
        option_type.as_json.merge(
          'option_values' => values.map(&:as_json)
        )
      end
    end  
  end
end 