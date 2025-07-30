#!/bin/bash

echo "🔍 Debugging Solidus Admin Routes..."

# First, let's see what the actual admin routes look like
echo "📋 Raw admin routes from rails routes:"
rails routes 2>/dev/null | grep -i admin | grep GET | head -10

echo ""
echo "🎯 Looking for specific admin patterns:"

# Check for different route patterns
echo "Admin root routes:"
rails routes 2>/dev/null | grep -E "admin.*GET.*/" | head -5

echo ""
echo "Product routes:"
rails routes 2>/dev/null | grep -E "admin.*product" | grep GET | head -3

echo ""
echo "Order routes:" 
rails routes 2>/dev/null | grep -E "admin.*order" | grep GET | head -3

echo ""
echo "User routes:"
rails routes 2>/dev/null | grep -E "admin.*user" | grep GET | head -3

echo ""
echo "🔧 Let's check the route names directly:"

# Create a more detailed route checker
cat > tmp_detailed_route_check.rb << 'EOF'
StateMachines::Machine.ignore_method_conflicts = true

puts "🔍 All route names containing 'admin':"
all_routes = Rails.application.routes.routes
admin_routes = all_routes.select { |route| route.name&.include?('admin') }

admin_routes.first(15).each do |route|
  puts "  #{route.name} -> #{route.path.spec}"
end

puts "\n🎯 Testing specific route helpers:"
test_routes = [
  'spree.admin_root_path',
  'spree.admin_products_path', 
  'spree.admin_orders_path',
  'spree.admin_users_path',
  'admin_root_path',
  'admin_products_path',
  'admin_orders_path'
]

test_routes.each do |route_helper|
  begin
    if route_helper.include?('spree.')
      helper_name = route_helper.split('.').last
      result = Spree::Core::Engine.routes.url_helpers.send(helper_name)
      puts "  ✓ #{route_helper} -> #{result}"
    else
      result = Rails.application.routes.url_helpers.send(route_helper)  
      puts "  ✓ #{route_helper} -> #{result}"
    end
  rescue => e
    puts "  ✗ #{route_helper} -> #{e.class}: #{e.message.split('.').first}"
  end
end
EOF

rails runner tmp_detailed_route_check.rb 2>/dev/null

# Clean up
rm tmp_detailed_route_check.rb

echo ""
echo "🚀 Based on the above, we can create the correct navigation!"