# frozen_string_literal: true

module Api
  class OrdersController < Spree::Api::BaseController
    before_action :set_order, only: [:show, :update, :destroy]
    before_action :load_order, only: [:available_shipping_methods]

    def index
      @orders = Spree::Order.includes(:line_items, :shipments, :payments)
                           .where(user: current_user)
                           .order(created_at: :desc)
      render json: @orders.as_json(include: [:line_items, :shipments, :payments])
    end

    def show
      render json: @order.as_json(include: [
        :line_items, 
        :bill_address, 
        :ship_address,
        { shipments: { include: :shipping_rates } },
        :payments
      ])
    end

    # GET /api/orders/:id/available_shipping_methods
    # Returns available shipping methods with rates for the order
    def available_shipping_methods
      if @order.shipments.empty?
        return render json: { 
          error: "Order must have a shipping address before shipping methods can be determined" 
        }, status: :unprocessable_entity
      end

      shipping_methods = []
      render json: @order.as_json(include: [
        { shipments: { include: { shipping_methods: { include: :shipping_rates } } } }
      ])

    end

    def create
      @order = Spree::Order.create(user: current_user, store: Spree::Store.default)
      render json: @order.as_json(include: [:line_items]), status: :created
    end

    def update
      if @order.update(order_params)
        render json: @order.as_json(include: [:line_items, :shipments, :payments])
      else
        render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @order.destroy
      render json: { message: 'Order deleted successfully' }
    end

  private

    def set_order
      @order = Spree::Order.find(params[:id])
    end

    def order_params
      params.require(:order).permit(:email, :special_instructions)
    end
  end
end 