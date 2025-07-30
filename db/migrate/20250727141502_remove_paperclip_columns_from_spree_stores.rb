class RemovePaperclipColumnsFromSpreeStores < ActiveRecord::Migration[7.1]
  def change
    remove_column :spree_stores, :hero_image_file_name, :string
    remove_column :spree_stores, :hero_image_content_type, :string
    remove_column :spree_stores, :hero_image_file_size, :integer
    remove_column :spree_stores, :hero_image_updated_at, :datetime
  end
end
