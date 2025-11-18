module Spree

    module Admin

        module OrdersControllerDecorator

            def mark_as_ready
                binding.pry
            end
        end
    end
end

Rails.application.config.to_prepare do
  Spree::Admin::OrdersController.prepend Spree::Admin::OrdersControllerDecorator
end



