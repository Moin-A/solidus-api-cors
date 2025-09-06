class AddIndexesForSpreeProductAssociations < ActiveRecord::Migration[7.0]
  def change
    # For master variant association: spree_products -> spree_variants (master)
    # Needed for: master: :images
    add_index :spree_variants, [:product_id, :is_master], 
              name: 'index_spree_variants_on_product_id_and_is_master',
              if_not_exists: true

    # For all variants association: spree_products -> spree_variants
    # Needed for: variants: :images (though product_id might already exist)
    add_index :spree_variants, :product_id, 
              name: 'index_spree_variants_on_product_id',
              if_not_exists: true

    # For images association: spree_variants -> spree_assets (polymorphic)
    # Needed for both: master: :images and variants: :images
    add_index :spree_assets, [:viewable_id, :viewable_type], 
              name: 'index_spree_assets_on_viewable',
              if_not_exists: true

    # More specific index for image assets only (optional but better performance)
    add_index :spree_assets, [:viewable_id, :viewable_type, :type], 
              name: 'index_spree_assets_on_viewable_and_type',
              if_not_exists: true

    # For the .available scope optimization (based on your earlier SQL)
    # Composite index for deleted_at and available_on
    add_index :spree_products, [:deleted_at, :available_on], 
              name: 'index_spree_products_on_deleted_at_and_available_on',
              if_not_exists: true

    # For spree_prices (used in .available scope EXISTS query)
    add_index :spree_prices, [:variant_id, :deleted_at], 
              name: 'index_spree_prices_on_variant_id_and_deleted_at',
              if_not_exists: true
  end
end