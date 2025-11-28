# frozen_string_literal: true

module Spree
  class Rating < Spree::Base
    has_many :products_ratings, dependent: :destroy, inverse_of: :rating
    has_many :products, through: :products_ratings

    validates_inclusion_of :rating, in: 0..5, message: 'must be between 0 and 5'
  end 
end

