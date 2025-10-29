# frozen_string_literal: true

module Api
  class CartController < BaseController
    before_action :set_cart

    def show
      render json: @cart.as_json(include: [:line_items, :shipments, :payments])
    end

    def add_item
      variant = Spree::Variant.find(params[:variant_id])
      quantity = params[:quantity] || 1

      line_item = @cart.add_item(variant, quantity)
      
      if line_item.save
        render json: @cart.as_json(include: [:line_items])
      else
        render json: { errors: line_item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update_item
      line_item = @cart.line_items.find(params[:line_item_id])
      
      if line_item.update(quantity: params[:quantity])
        render json: @cart.as_json(include: [:line_items])
      else
        render json: { errors: line_item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def remove_item
      line_item = @cart.line_items.find(params[:line_item_id])
      line_item.destroy
      
      render json: @cart.as_json(include: [:line_items])
    end

    def empty
      @cart.line_items.destroy_all
      render json: { message: 'Cart emptied successfully' }
    end

    def checkout
      # This would typically involve more complex checkout logic
      # For now, we'll just return the cart with checkout info
      render json: {
        cart: @cart.as_json(include: [:line_items]),
        available_payment_methods: Spree::PaymentMethod.available,
        available_shipping_methods: Spree::ShippingMethod.available
      }
    end

    private

    def set_cart
      @cart = Spree::Order.incomplete.find_or_create_by(user: current_user, store: Spree::Store.default)
    end
  end
end 