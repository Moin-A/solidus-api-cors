namespace :setup_cod_payment_method do
  desc "Setup Cash on Delivery payment method"
  task setup: :environment do
    payment_method = Spree::PaymentMethod.find_or_initialize_by(name: "Cash on Delivery")
    payment_method.update!(
      position: 1,
      type: 'Spree::PaymentMethod::Check',
      auto_capture: false,
      available_to_admin: true,
      active: true,
      description: "Pay with cash upon delivery."
    )
  end
end