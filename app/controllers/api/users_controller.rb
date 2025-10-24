# frozen_string_literal: true

module Api
  class UsersController < BaseController
    before_action :set_user, only: [:show, :update]

    def show
      render json: @user.as_json(include: [:orders, :addresses])
    end

    def update
      if @user.update(user_params)
        render json: @user.as_json(include: [:orders, :addresses])
      else
        render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def profile
      render json: {
        user: current_user.as_json(include: [:orders, :addresses]),
        orders_count: current_user.orders.count,
        total_spent: current_user.orders.complete.sum(:total)
      }
    end

    def addresses
      @addresses = current_user.addresses
      
      render json:  @addresses.as_json(
          include: {user_address: {only: [:default_billing], methods: [:default_shipping]}}
        )
    end

    def create_address
      @address = current_user.save_in_address_book(
        address_params,
        default_params,      # default = false (set to true if this should be the default address)
        :billing   # address_type (:shipping or :billing)
      )
      
      if @address&.persisted?
        
        render json: @address.as_json(
          include: {user_address: {only: [:default_billing], methods: [:default_shipping]}}
        ), status: :created
      else
        render json: { errors: @address&.errors&.full_messages || ["Invalid address"] }, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = Spree::User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :firstname, :lastname, :phone)
    end

    def address_params
      permitted = params.require(:address).permit( :address1, :address2, :city, :state_id, :zipcode, :country_id, :phone, :name).except(:address_type, :default)
    end

    def address_type_params
      params.require(:address).permit(:address_type)
    end

     def default_params
      params.require(:address).permit(:default)
    end

    def current_user
      # This would be implemented based on your authentication strategy
      Spree::User.first
    end
  end
end 