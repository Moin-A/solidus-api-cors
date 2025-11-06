# frozen_string_literal: true

namespace :gst do
  desc "Add GST tax rates for Arunachal Pradesh"
  task add_arunachal: :environment do
    puts "🇮🇳 Adding GST for Arunachal Pradesh..."
    puts ""
    
    # Find Arunachal Pradesh state
    ap_state = Spree::State.find_by(name: 'Arunachal Pradesh')
    
    unless ap_state
      puts "❌ Arunachal Pradesh state not found!"
      exit
    end
    
    # Create zone for Arunachal Pradesh
    ap_zone = Spree::Zone.find_or_create_by!(name: 'Arunachal Pradesh') do |zone|
      zone.description = 'Arunachal Pradesh for GST'
    end
    
    # Add state to zone if not already added
    unless ap_zone.zone_members.exists?(zoneable: ap_state)
      ap_zone.zone_members.create!(zoneable: ap_state)
      puts "✅ Zone created for Arunachal Pradesh"
    else
      puts "✓ Zone already exists for Arunachal Pradesh"
    end
    
    # GST Rates: CGST + SGST = Total GST
    # Clothing: 12% (6% CGST + 6% SGST)
    # Electronics: 18% (9% CGST + 9% SGST)
    # Default: 18% (9% CGST + 9% SGST)
    
    gst_config = [
      { category: 'Clothing', cgst: 6, sgst: 6 },
      { category: 'Electronics', cgst: 9, sgst: 9 },
      { category: 'Default', cgst: 9, sgst: 9 }
    ]
    
    gst_config.each do |config|
      tax_category = Spree::TaxCategory.find_by(name: config[:category])
      
      unless tax_category
        puts "  ⚠️  Tax category '#{config[:category]}' not found, skipping..."
        next
      end
      
      # Create CGST
      cgst = Spree::TaxRate.find_or_initialize_by(
        name: "#{config[:category]} CGST @ #{config[:cgst]}%",
        zone: ap_zone
      )
      cgst.amount = config[:cgst] / 100.0
      cgst.included_in_price = false
      cgst.level = :item
      cgst.calculator = Spree::Calculator::DefaultTax.new if cgst.calculator.nil?
      cgst.save!
      
      # Link to tax category
      unless cgst.tax_categories.include?(tax_category)
        cgst.tax_categories << tax_category
      end
      
      # Create SGST  
      sgst = Spree::TaxRate.find_or_initialize_by(
        name: "#{config[:category]} SGST @ #{config[:sgst]}%",
        zone: ap_zone
      )
      sgst.amount = config[:sgst] / 100.0
      sgst.included_in_price = false
      sgst.level = :item
      sgst.calculator = Spree::Calculator::DefaultTax.new if sgst.calculator.nil?
      sgst.save!
      
      # Link to tax category
      unless sgst.tax_categories.include?(tax_category)
        sgst.tax_categories << tax_category
      end
      
      puts "✅ #{config[:category]}: CGST #{config[:cgst]}% + SGST #{config[:sgst]}% = Total #{config[:cgst] + config[:sgst]}%"
    end
    
    puts ""
    puts "=" * 60
    puts "✅ GST configuration completed for Arunachal Pradesh!"
    puts "=" * 60
  end
end

