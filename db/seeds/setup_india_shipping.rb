# frozen_string_literal: true

# Setup India Shipping Configuration for Solidus
# Run with: rails runner db/seeds/setup_india_shipping.rb

puts "🇮🇳 Setting up India shipping configuration..."

# 1. Find India country
india = Spree::Country.find_by(iso: "IN") || Spree::Country.find_by(iso: "IND")

if india.nil?
  puts "❌ India country not found. Creating it..."
  india = Spree::Country.create!(
    name: "India",
    iso: "IN",
    iso3: "IND",
    numcode: 356,
    states_required: true
  )
  puts "✅ Created India country (ID: #{india.id})"
else
  puts "✅ Found India (ID: #{india.id}, Name: #{india.name})"
end

# 2. Create India shipping zone
india_zone = Spree::Zone.find_or_create_by!(name: "India Shipping Zone") do |z|
  z.description = "Shipping within India"
  puts "✅ Created India Shipping Zone"
end

# 3. Add India to the zone
zone_member = india_zone.zone_members.find_or_create_by!(zoneable: india)
puts "✅ Added India to zone (Zone members: #{india_zone.zone_members.count})"

# 4. Create/find shipping category
category = Spree::ShippingCategory.find_or_create_by!(name: "Default") do |c|
  puts "✅ Created Default shipping category"
end
puts "✅ Shipping category: #{category.name} (ID: #{category.id})"

# 5. Create India-specific shipping method
india_method = Spree::ShippingMethod.find_by(name: "India Standard Shipping")

if india_method.nil?
  india_method = Spree::ShippingMethod.new(
    name: "India Standard Shipping",
    admin_name: "India Standard",
    available_to_users: true,
    available_to_all: true
  )
  
  # Must add category BEFORE saving (validation requires it)
  india_method.shipping_categories << category
  india_method.zones << india_zone
  india_method.stores << Spree::Store.default
  
  # Create calculator BEFORE saving (validation requires it)
  india_method.calculator = Spree::Calculator::Shipping::FlatRate.new(
    preferences: {
      amount: 50.00,
      currency: "INR"
    }
  )
  
  india_method.save!
  puts "✅ Created India Standard Shipping method (ID: #{india_method.id})"
  puts "✅ Created flat rate calculator (₹50.00 INR)"
else
  puts "✅ Found existing India Standard Shipping (ID: #{india_method.id})"
  
  # 6. Associate shipping method with zone if not already
  unless india_method.zones.include?(india_zone)
    india_method.zones << india_zone
    puts "✅ Associated shipping method with India zone"
  end
  
  # 7. Associate shipping method with category if not already
  unless india_method.shipping_categories.include?(category)
    india_method.shipping_categories << category
    puts "✅ Associated shipping method with shipping category"
  end
end

# 8. Update calculator if method already existed
if india_method.calculator && india_method.calculator.persisted?
  india_method.calculator.update!(
    preferences: {
      amount: 50.00,
      currency: "INR"
    }
  )
  puts "✅ Updated calculator to ₹50.00 INR"
end

# 9. Assign shipping category to all products
products_updated = Spree::Product.where(shipping_category_id: nil).update_all(shipping_category_id: category.id)
puts "✅ Assigned shipping category to #{products_updated} products"

# Also update variants if needed
variants_updated = Spree::Variant.where(shipping_category_id: nil).update_all(shipping_category_id: category.id)
puts "✅ Assigned shipping category to #{variants_updated} variants"

# 10. Update store currency to INR (optional)
default_store = Spree::Store.default
if default_store.default_currency != "INR"
  default_store.update!(default_currency: "INR")
  puts "✅ Updated store default currency to INR"
end

puts "\n" + "="*60
puts "🎉 India Shipping Setup Complete!"
puts "="*60

# 11. Verification
puts "\n📋 Verification:"
puts "- Shipping Method: #{india_method.name}"
puts "- Zone: #{india_zone.name}"
puts "- Countries in zone: #{india_zone.countries.pluck(:name).join(', ')}"
puts "- Shipping rate: ₹#{india_method.calculator.preferences[:amount]} #{india_method.calculator.preferences[:currency]}"
puts "- Products with shipping category: #{Spree::Product.where(shipping_category_id: category.id).count}"
puts "- Store currency: #{default_store.default_currency}"

# 12. Test with an order (if exists)
if Spree::Order.exists?
  test_order = Spree::Order.last
  if test_order.ship_address&.country_id == india.id
    puts "\n🧪 Testing with Order ##{test_order.number}:"
    
    # Try to get available shipping methods
    if test_order.shipments.any?
      package = test_order.shipments.first.to_package
      available_methods = package.shipping_methods
        .available_to_store(test_order.store)
        .available_for_address(test_order.ship_address)
      
      puts "- Available shipping methods: #{available_methods.count}"
      available_methods.each do |method|
        puts "  • #{method.name}"
      end
      
      # Try to calculate rates
      begin
        rates = Spree::Stock::Estimator.new.shipping_rates(package)
        puts "- Calculated shipping rates: #{rates.count}"
        rates.each do |rate|
          puts "  • #{rate.name}: ₹#{rate.cost}"
        end
      rescue => e
        puts "- Rate calculation error: #{e.message}"
      end
    else
      puts "- No shipments found for testing"
    end
  else
    puts "\n⚠️  Test order's address is not in India (country_id: #{test_order.ship_address&.country_id})"
    puts "   Create an order with Indian shipping address to test."
  end
end

puts "\n✅ Script completed successfully!"

