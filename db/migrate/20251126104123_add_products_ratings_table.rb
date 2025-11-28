class AddProductsRatingsTable < ActiveRecord::Migration[7.2]
  def change

    create_table :spree_ratings do |t|
      t.text :comment
       # rating value between 0 and 5 limit: 1
      t.integer :rating, null: false, default: 0
      t.timestamps
    end

    create_table :spree_products_ratings do |t| 
      t.references :product, foreign_key: { to_table: :spree_products }
      t.references :rating, foreign_key: { to_table: :spree_ratings }
      t.timestamps
    end 

    add_index :spree_products_ratings, [:product_id, :rating_id], unique: true, name: 'index_spree_products_ratings_on_product_id_and_rating_id'
  end
end
