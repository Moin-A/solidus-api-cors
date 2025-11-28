module Spree
  class ProductsRating < Spree::Base

    belongs_to :product, class_name: 'Spree::Product', inverse_of: :products_ratings, optional: true
    belongs_to :rating, class_name: 'Spree::Rating', inverse_of: :products_ratings, optional: true

    validates_uniqueness_of :rating_id, scope: :product_id
  end
end 