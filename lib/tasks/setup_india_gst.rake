# frozen_string_literal: true

namespace :gst do
  desc "Setup GST (CGST + SGST) for all Indian states"
  task setup_all_states: :environment do
    puts "🇮🇳 Setting up GST for all Indian states..."
    puts ""
    
    # GST Rates by category
    gst_rates = {
      'Clothing' => 12,      # 6% CGST + 6% SGST
      'Electronics' => 18,   # 9% CGST + 9% SGST
      'Default' => 18        # 9% CGST + 9% SGST
    }
    
    # Get all Indian states
    india = Spree::Country.find_by(iso: 'IN')
    unless india
      puts "❌ India country not found! Please ensure India is in your database."
      exit
    end
    
    indian_states = Spree::State.where(country_id: india.id)
    
    if indian_states.empty?
      puts "❌ No Indian states found! Please seed states first."
      exit
    end
    
    puts "Found #{indian_states.count} Indian states"
    puts ""
    
    success_count = 0
    error_count = 0
    
    indian_states.each do |state|
      begin
        # Create or find zone for this state
        zone = Spree::Zone.find_or_create_by!(name: state.name)
        
        # Add state to zone if not already added
        unless zone.zone_members.exists?(zoneable: state)
          zone.zone_members.create!(zoneable: state)
        end
        
        # Create tax rates for each category
        gst_rates.each do |category_name, total_rate|
          tax_category = Spree::TaxCategory.find_by(name: category_name)
          
          unless tax_category
            puts "  ⚠️  Tax category '#{category_name}' not found, skipping..."
            next
          end
          
          cgst_rate = total_rate / 2.0
          sgst_rate = total_rate / 2.0
          
          # Create CGST
          cgst = Spree::TaxRate.find_or_create_by!(
            name: "#{category_name} CGST @ #{cgst_rate.to_i}%",
            zone: zone,
            amount: cgst_rate / 100.0,
            level: :item
          ) do |rate|
            rate.included_in_price = false
          end
          
          # Link to tax category
          unless cgst.tax_categories.include?(tax_category)
            cgst.tax_categories << tax_category
          end
          
          # Create SGST
          sgst = Spree::TaxRate.find_or_create_by!(
            name: "#{category_name} SGST @ #{sgst_rate.to_i}%",
            zone: zone,
            amount: sgst_rate / 100.0,
            level: :item
          ) do |rate|
            rate.included_in_price = false
          end
          
          # Link to tax category
          unless sgst.tax_categories.include?(tax_category)
            sgst.tax_categories << tax_category
          end
        end
        
        puts "✅ #{state.name}: CGST + SGST configured for #{gst_rates.keys.join(', ')}"
        success_count += 1
        
      rescue => e
        puts "❌ #{state.name}: Error - #{e.message}"
        error_count += 1
      end
    end
    
    puts ""
    puts "=" * 60
    puts "Summary:"
    puts "  ✅ Success: #{success_count} states"
    puts "  ❌ Errors: #{error_count} states"
    puts "  📊 Total tax rates created: ~#{success_count * gst_rates.count * 2}"
    puts "=" * 60
  end
  
  desc "Show GST configuration for a specific state"
  task :show, [:state_name] => :environment do |t, args|
    state_name = args[:state_name] || 'Arunachal Pradesh'
    
    state = Spree::State.find_by("name ILIKE ?", state_name)
    
    unless state
      puts "❌ State '#{state_name}' not found"
      exit
    end
    
    puts "🇮🇳 GST Configuration for #{state.name}"
    puts ""
    
    zone = Spree::Zone.find_by(name: state.name)
    
    if zone
      tax_rates = Spree::TaxRate.where(zone: zone)
      
      if tax_rates.any?
        tax_rates.group_by { |r| r.tax_categories.first&.name }.each do |category, rates|
          puts "#{category}:"
          rates.each do |rate|
            puts "  - #{rate.name}: #{rate.amount * 100}%"
          end
        end
      else
        puts "❌ No tax rates configured for #{state.name}"
      end
    else
      puts "❌ No zone found for #{state.name}"
    end
  end
end

