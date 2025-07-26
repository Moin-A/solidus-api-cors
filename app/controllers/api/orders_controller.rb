# frozen_string_literal: true

module Api
  class OrdersController < BaseController
    before_action :set_order, only: [:show, :update, :destroy]

    def index
      @orders = Spree::Order.includes(:line_items, :shipments, :payments)
                           .where(user: current_user)
                           .order(created_at: :desc)
      render json: @orders.as_json(include: [:line_items, :shipments, :payments])
    end

    def show
      render json: @order.as_json(include: [:line_items, :shipments, :payments, :addresses])
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

    def current_user
      # This would be implemented based on your authentication strategy
      # For now, we'll use the first user or implement token-based auth
      Spree::User.first
    end
  end
end 