class AddHeroImageToSpreeStores < ActiveRecord::Migration[7.0]
  def change
    add_column :spree_stores, :hero_image_file_name, :string
    add_column :spree_stores, :hero_image_content_type, :string
    add_column :spree_stores, :hero_image_file_size, :integer
    add_column :spree_stores, :hero_image_updated_at, :datetime
    
    # Alternative: if using Active Storage (Rails 5.2+)
    # No migration needed, just add has_one_attached :hero_image to Store model
  end
end