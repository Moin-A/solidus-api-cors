#!/bin/bash

# Setup Sample Fashion Products Script
# This script demonstrates how to use the sample product rake tasks

echo "🎯 Setting up Sample Fashion Products"
echo "====================================="

# Check if we're in the right directory
if [ ! -f "Gemfile" ]; then
    echo "❌ Error: Please run this script from the Rails application root directory"
    exit 1
fi

echo "📋 Step 1: Listing available sample images..."
rails sample:list_sample_images

echo ""
echo "🛍️  Step 2: Creating fashion products with sample images..."
rails sample:fashion_products

echo ""
echo "✅ Setup complete! You can now:"
echo "   - View products in admin: http://localhost:3001/admin/products"
echo "   - Run 'rails sample:help' to see all available tasks"
echo "   - Run 'rails sample:clean_fashion_products' to clean up (use with caution!)"

echo ""
echo "📊 Current fashion products count:"
rails runner 'puts "Total Fashion products: #{Spree::Taxon.find_by(name: "Fashion")&.products&.count || 0}"'
