class DeleteProductsRatingTable < ActiveRecord::Migration[7.2]
  def up
    drop_table :spree_products_ratings do |t|
      t.references :product, null: false, foreign_key: { to_table: :spree_products }
      t.references :rating, null: false, foreign_key: { to_table: :spree_ratings }
    end 

   add_reference :spree_ratings, :line_item, foreign_key: { to_table: :spree_line_items }, index: true
  end

  def down
    create_table :spree_products_ratings do |t|
      t.references :product, null: false, foreign_key: { to_table: :spree_products }
      t.references :rating, null: false, foreign_key: { to_table: :spree_ratings }
    end
    # command to remove reference
    # remove_reference :table_name, fk_name, options
    remove_reference :spree_ratings, :line_item, foreign_key: { to_table: :spree_line_items }, index: true
  end
end
