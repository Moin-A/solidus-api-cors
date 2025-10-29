# frozen_string_literal: true

# Create multiple shipping methods for India

puts "🚚 Setting up India shipping methods..."

# Get references
india = Spree::Country.find(105)
india_zone = Spree::Zone.find_or_create_by!(name: "India Shipping Zone") do |z|
  z.description = "Shipping within India"
end
india_zone.zone_members.find_or_create_by!(zoneable: india)

category = Spree::ShippingCategory.find_or_create_by!(name: "Default")
store = Spree::Store.default

# Shipping methods configuration
shipping_methods = [
  {
    name: "Standard Shipping",
    admin_name: "Standard",
    cost: 50.00,
    description: "5-7 business days"
  },
  {
    name: "Express Shipping",
    admin_name: "Express",
    cost: 150.00,
    description: "2-3 business days"
  },
  {
    name: "Next Day Delivery",
    admin_name: "Next Day",
    cost: 300.00,
    description: "1 business day"
  }
]

# Create each method
shipping_methods.each do |config|
  method = Spree::ShippingMethod.find_by(name: config[:name])
  
  if method
    puts "✓ Found existing: #{config[:name]}"
    
    # Update calculator cost
    method.calculator.update!(
      preferences: {
        amount: config[:cost],
        currency: nil  # Accept any currency
      }
    )
    puts "  Updated cost to ₹#{config[:cost]}"
  else
    # Create new method
    method = Spree::ShippingMethod.new(
      name: config[:name],
      admin_name: config[:admin_name],
      available_to_users: true,
      available_to_all: true
    )
    
    # Add associations BEFORE saving
    method.shipping_categories << category
    method.zones << india_zone
    method.stores << store
    
    # Create calculator
    method.calculator = Spree::Calculator::Shipping::FlatRate.new(
      preferences: {
        amount: config[:cost],
        currency: nil
      }
    )
    
    method.save!
    puts "✅ Created: #{config[:name]} (₹#{config[:cost]})"
  end
end

# Assign category to all products
Spree::Variant.where(shipping_category_id: nil).update_all(shipping_category_id: category.id)

puts "\n📊 Summary:"
puts "Shipping Methods: #{Spree::ShippingMethod.count}"
Spree::ShippingMethod.all.each do |m|
  cost = m.calculator&.preferences&.dig(:amount) || 0
  puts "  - #{m.name}: ₹#{cost}"
end

puts "\n🎉 Done! Orders will now have 3 shipping options."



