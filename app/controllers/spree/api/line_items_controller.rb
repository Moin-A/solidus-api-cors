# frozen_string_literal: true

module Spree
  module Api
    # LineItems controller brought to application level
    # Overrides gem's Spree::Api::LineItemsController
    class LineItemsController < Spree::Api::BaseController
    before_action :load_order, only: [:create, :update, :destroy]
    around_action :lock_order, only: [:create, :update, :destroy]

    def create
      variant = Spree::Variant.find(params[:line_item][:variant_id])
      
      @line_item = @order.contents.add(
        variant,
        params[:line_item][:quantity] || 1,
        options: line_item_params[:options].to_h
      )

      if @line_item.persisted?
        render json: @line_item.as_json(include: { variant: { include: :product } }), status: :created
      else
        render json: { errors: @line_item.errors.full_messages }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      @line_item = find_line_item
      
      if @order.contents.update_cart(line_items_attributes)
        @line_item.reload
        render json: @line_item.as_json(include: { variant: { include: :product } })
      else
        render json: { errors: @line_item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @line_item = find_line_item
      @order.contents.remove_line_item(@line_item)
      head :no_content
    end

    private

    def find_line_item
      id = params[:id].to_i
      @order.line_items.detect { |line_item| line_item.id == id } ||
        raise(ActiveRecord::RecordNotFound)
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Line item not found' }, status: :not_found
    end

    def line_items_attributes
      { 
        line_items_attributes: {
          id: params[:id],
          quantity: params[:line_item][:quantity],
          options: line_item_params[:options] || {}
        } 
      }
    end

    def line_item_params
      params.require(:line_item).permit(:quantity, :variant_id, options: {})
    end

    def order_id
      params[:order_id]
    end

    def lock_order
      @order.with_lock do
        yield
      end
    end
    end
  end
end

