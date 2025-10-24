Spree::User.class_eval do
  devise :confirmable unless devise_modules.include?(:confirmable)
  include UserVerification
end
