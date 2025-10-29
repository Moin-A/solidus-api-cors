# frozen_string_literal: true

# Convert all products and prices from USD to INR

puts "🔄 Converting all products to INR..."

# Configuration
CONVERT_AMOUNTS = false  # Set to true to multiply prices by conversion rate
CONVERSION_RATE = 82.0   # USD to INR rate

# 1. Show current state
puts "\n=== BEFORE ==="
usd_variants = Spree::Variant.where(cost_currency: 'USD').count
usd_prices = Spree::Price.where(currency: 'USD').count
puts "Variants with USD: #{usd_variants}"
puts "Prices with USD: #{usd_prices}"

# 2. Update variants
if CONVERT_AMOUNTS
  puts "\n🔢 Converting variant costs with rate: #{CONVERSION_RATE}..."
  Spree::Variant.where(cost_currency: 'USD').find_each do |variant|
    if variant.cost_price
      old_cost = variant.cost_price
      new_cost = (old_cost * CONVERSION_RATE).round(2)
      variant.update!(cost_price: new_cost, cost_currency: 'INR')
      puts "  #{variant.sku}: $#{old_cost} → ₹#{new_cost}"
    else
      variant.update!(cost_currency: 'INR')
    end
  end
else
  updated = Spree::Variant.where(cost_currency: 'USD').update_all(cost_currency: 'INR')
  puts "✅ Updated #{updated} variants to INR (amounts unchanged)"
end

# 3. Update prices
if CONVERT_AMOUNTS
  puts "\n🔢 Converting prices with rate: #{CONVERSION_RATE}..."
  Spree::Price.where(currency: 'USD').find_each do |price|
    old_amount = price.amount
    new_amount = (old_amount * CONVERSION_RATE).round(2)
    price.update!(amount: new_amount, currency: 'INR')
    puts "  #{price.variant.sku}: $#{old_amount} → ₹#{new_amount}"
  end
else
  updated = Spree::Price.where(currency: 'USD').update_all(currency: 'INR')
  puts "✅ Updated #{updated} prices to INR (amounts unchanged)"
end

# 4. Update global config
Spree::Config[:currency] = "INR"
Spree::Config.save!
puts "\n✅ Updated Spree::Config[:currency] to INR"

# 5. Update store
Spree::Store.find_each do |store|
  store.update!(default_currency: 'INR')
  puts "✅ Updated store '#{store.name}' to INR"
end

# 6. Update existing orders (optional - uncomment if needed)
# puts "\n⚠️  Updating existing orders to INR..."
# Spree::Order.where(currency: 'USD').update_all(currency: 'INR')

# 7. Show final state
puts "\n=== AFTER ==="
puts "Variants with INR: #{Spree::Variant.where(cost_currency: 'INR').count}"
puts "Prices with INR: #{Spree::Price.where(currency: 'INR').count}"
puts "Variants still USD: #{Spree::Variant.where(cost_currency: 'USD').count}"
puts "Prices still USD: #{Spree::Price.where(currency: 'USD').count}"

puts "\n🎉 Currency conversion complete!"



