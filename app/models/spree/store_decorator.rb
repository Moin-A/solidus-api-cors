# app/models/spree/store_decorator.rb
Spree::Store.prepend Spree::StoreDecorator
module Spree
  module StoreDecorator
  # Using Active Storage (Rails 5.2+) - RECOMMENDED
    has_one_attached :hero_image
    
    # Add validation for Active Storage
    validate :acceptable_hero_image
    
    # Virtual attribute for removing hero image
    attr_accessor :remove_hero_image
    
    # Handle hero image removal
    after_save :purge_hero_image, if: :remove_hero_image?
    
    private
    
    def acceptable_hero_image
      return unless hero_image.attached?
      
      unless hero_image.blob.byte_size <= 5.megabytes
        errors.add(:hero_image, "is too big (should be at most 5MB)")
      end
      
      acceptable_types = ["image/jpeg", "image/jpg", "image/png", "image/gif"]
      unless acceptable_types.include?(hero_image.blob.content_type)
        errors.add(:hero_image, "must be a JPEG, JPG, PNG or GIF")
      end
    end
    
    def remove_hero_image?
      remove_hero_image == '1' || remove_hero_image == true
    end
    
    def purge_hero_image
      hero_image.purge if hero_image.attached?
    end
  end 
end