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
        params[:address][:default] == true || params[:address][:default] == "true",  # Convert to boolean
        params[:address][:address_type]&.to_sym || :shipping  # Convert to symbol
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
      params.require(:address).permit(:address1, :address2, :city, :state_id, :zipcode, :country_id, :phone, :name)
    end
  end
end 