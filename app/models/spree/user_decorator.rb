Spree::User.class_eval do
  devise :confirmable unless devise_modules.include?(:confirmable)
  has_many :product_ratings, foreign_key: "user_id", class_name: "Spree::Rating", inverse_of: :user
  include UserVerification
end
