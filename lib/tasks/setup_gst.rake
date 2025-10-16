# frozen_string_literal: true

namespace :gst do
  desc "Setup GST rates for Assam (Electronics 18%, Clothing 12%)"
  task setup: :environment do
    puts "\n========== GST Setup for Assam =========="

    # Step 1: Create Zone for Assam
    puts "\n1. Setting up Assam Zone..."
    assam_zone = Spree::Zone.find_by(name: 'Assam') || create_assam_zone
    puts "✓ Assam Zone: #{assam_zone.name}"

    # Step 2: Create Tax Categories
    puts "\n2. Creating Tax Categories..."
    electronics_category = create_tax_category('Electronics', 'Electronics products including phones, laptops, tablets')
    clothing_category = create_tax_category('Clothing', 'Readymade clothing items')
    puts "✓ Electronics Tax Category created"
    puts "✓ Clothing Tax Category created"

    # Step 3: Create Shipping Category
    puts "\n3. Creating Shipping Category..."
    shipping_category = create_shipping_category
    puts "✓ Shipping Category created: #{shipping_category.name}"

    # Step 4: Create Tax Rates
    puts "\n4. Creating Tax Rates..."
    
    # Electronics: 18% (9% CGST + 9% SGST)
    create_tax_rate(
      'Electronics CGST @ 9%',
      electronics_category,
      assam_zone,
      9.0,
      'CGST'
    )
    create_tax_rate(
      'Electronics SGST @ 9%',
      electronics_category,
      assam_zone,
      9.0,
      'SGST'
    )
    puts "✓ Electronics Tax Rates created (9% CGST + 9% SGST = 18%)"
    
    # Clothing: 12% (6% CGST + 6% SGST)
    create_tax_rate(
      'Clothing CGST @ 6%',
      clothing_category,
      assam_zone,
      6.0,
      'CGST'
    )
    create_tax_rate(
      'Clothing SGST @ 6%',
      clothing_category,
      assam_zone,
      6.0,
      'SGST'
    )
    puts "✓ Clothing Tax Rates created (6% CGST + 6% SGST = 12%)"

    # Step 5: Create Sample Products
    puts "\n5. Creating Sample Products..."
    
    # Electronics products
    electronics_products = [
      { name: 'Samsung Galaxy S24', price: 75000, description: 'Latest flagship smartphone' },
      { name: 'MacBook Pro M3', price: 145000, description: 'Professional laptop' },
      { name: 'Apple iPad Air', price: 65000, description: 'Tablet for productivity' }
    ]
    
    electronics_products.each do |product_data|
      create_product(
        product_data[:name],
        product_data[:price],
        product_data[:description],
        electronics_category
      )
    end
    puts "✓ 3 Electronics products created"
    
    # Clothing products
    clothing_products = [
      { name: 'Denim Jeans', price: 2000, description: 'Classic blue denim jeans' },
      { name: 'Cotton T-Shirt', price: 500, description: 'Comfortable cotton t-shirt' },
      { name: 'Traditional Kurta', price: 1500, description: 'Elegant traditional kurta' }
    ]
    
    clothing_products.each do |product_data|
      create_product(
        product_data[:name],
        product_data[:price],
        product_data[:description],
        clothing_category
      )
    end
    puts "✓ 3 Clothing products created"

    # Summary
    puts "\n========== Setup Complete =========="
    puts "\nSummary:"
    puts "  - Zone: Assam (India)"
    puts "  - Tax Categories: 2 (Electronics, Clothing)"
    puts "  - Tax Rates: 4 (2 for Electronics, 2 for Clothing)"
    puts "  - Sample Products: 6 (3 Electronics, 3 Clothing)"
    puts "\nTax Breakdown:"
    puts "  - Electronics: 18% (9% CGST + 9% SGST)"
    puts "  - Clothing: 12% (6% CGST + 6% SGST)"
    puts "\nExample Prices (with tax):"
    puts "  - Samsung Galaxy S24: ₹75,000 + ₹13,500 tax = ₹88,500"
    puts "  - Denim Jeans: ₹2,000 + ₹240 tax = ₹2,240"
    puts "\n"
  end

  private

  # Create Assam Zone with India country and Assam state
  def create_assam_zone
    # Find or create India
    india = Spree::Country.find_by(iso: 'IN')
    raise "India country not found! Please ensure India is in your database." unless india

    # Find or create Assam state
    assam_state = Spree::State.find_by(country_id: india.id, abbr: 'AS')
    raise "Assam state not found! Please ensure Assam state is created." unless assam_state

    # Create zone
    zone = Spree::Zone.create!(
      name: 'Assam',
      description: 'Assam State, India'
    )

    # Add state to zone
    zone.zone_members.create!(zoneable: assam_state)

    zone
  end

  # Create Tax Category
  def create_tax_category(name, description)
    Spree::TaxCategory.find_or_create_by!(
      name: name,
      description: description
    )
  end

  # Create Shipping Category
  def create_shipping_category
    Spree::ShippingCategory.find_or_create_by!(name: 'Default')
  end

  # Create Tax Rate
  def create_tax_rate(name, tax_category, zone, rate, tax_type)
    tax_rate = Spree::TaxRate.find_or_create_by!(
      name: name,
      zone: zone,
      amount: rate / 100.0,
      included_in_price: false
    ) do |tr|
      # Create the DefaultTax calculator when creating tax rate
      tr.build_calculator(type: 'Spree::Calculator::DefaultTax')
    end
    
    # Create calculator if it doesn't exist
    tax_rate.build_calculator(type: 'Spree::Calculator::DefaultTax') unless tax_rate.calculator
    tax_rate.calculator&.save!
    
    # Associate tax category with tax rate through join table
    tax_rate.tax_categories << tax_category unless tax_rate.tax_categories.include?(tax_category)
    
    tax_rate
  end

  # Create Product with Tax Category
  def create_product(name, price, description, tax_category)
    # Get or create shipping category
    shipping_category = Spree::ShippingCategory.find_by(name: 'Default') || create_shipping_category
    
    # Create unique SKU
    sku = name.upcase.gsub(/\s+/, '-')
    
    # Find or create product by name
    product = Spree::Product.find_or_create_by!(name: name) do |prod|
      prod.slug = name.downcase.gsub(/\s+/, '-')
      prod.description = description
      prod.price = price
      prod.shipping_category = shipping_category
    end

    # Find or create variant by SKU
    variant = Spree::Variant.find_or_create_by!(sku: sku) do |var|
      var.product = product
      var.price = price
    end

    # Add tax category to product
    product.tax_category = tax_category
    product.save!

    product
  end
end
