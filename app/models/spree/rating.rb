# frozen_string_literal: true

module Spree
  class Rating < Spree::Base
    belongs_to :line_item, inverse_of: :rating, optional: true

    validates_inclusion_of :rating, in: 0..5, message: 'must be between 0 and 5'
  end 
end

