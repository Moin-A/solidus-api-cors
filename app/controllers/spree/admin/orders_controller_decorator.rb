# frozen_string_literal: true

module Spree
  module Admin
    module OrdersControllerDecorator
      def mark_ready
        
        @shipment = Spree::Shipment.find_by(number: params[:shipment_number])
        @order = @shipment.order
        authorize! :update, @shipment
          binding.pry
        if @shipment.pending? && @shipment.can_transition_from_pending_to_ready?
          @shipment.ready!
          @order.update(payment_state: 'ready') if @order.cod?
          flash[:success] = "Shipment #{@shipment.number} marked as ready"
        else
          flash[:error] = "Cannot mark shipment as ready. Current state: #{@shipment.state}"
        end
        
        redirect_to edit_admin_order_path(@order)
      rescue => e
        flash[:error] = "Error: #{e.message}"
        binding.pry
        redirect_to  edit_admin_order_path(@order.id)
      end
      
      def ship_shipment
        @shipment = Spree::Shipment.find_by(number: params[:shipment_number])
        @order = @shipment.order
        
        authorize! :ship, @shipment
        
        if @shipment.ready?
          @shipment.suppress_mailer = (params[:send_mailer] != 'true')
          @shipment.ship!
          flash[:success] = "Shipment #{@shipment.number} has been shipped"
        else
          flash[:error] = "Cannot ship shipment. Current state: #{@shipment.state}"
        end
        
        redirect_to edit_admin_order_path(@order)
      rescue => e
        flash[:error] = "Error: #{e.message}"
        redirect_to edit_admin_order_path(@order)
      end
      Spree::Admin::OrdersController.prepend(self)
    end
  end
end
