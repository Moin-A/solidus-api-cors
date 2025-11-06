# frozen_string_literal: true

namespace :orders do
  desc "Rebuild shipments for pending orders to use single shipment configuration"
  task rebuild_shipments: :environment do
    # Find orders that:
    # - Are not completed
    # - Have pending shipments
    # - Have more than 1 shipment
    orders = Spree::Order.where(state: ['delivery', 'payment'])
                         .joins(:shipments)
                         .group('spree_orders.id')
                         .having('COUNT(spree_shipments.id) > 1')
                         .where(spree_shipments: { state: 'pending' })

    puts "Found #{orders.count} orders with multiple pending shipments"
    
    success_count = 0
    error_count = 0
    
    orders.find_each do |order|
      begin
        old_count = order.shipments.count
        order.create_proposed_shipments
        order.recalculate
        new_count = order.shipments.count
        
        puts "✅ Order #{order.number}: #{old_count} shipments → #{new_count} shipment(s)"
        success_count += 1
      rescue => e
        puts "❌ Order #{order.number}: Error - #{e.message}"
        error_count += 1
      end
    end
    
    puts "\n" + "=" * 50
    puts "Summary:"
    puts "  Success: #{success_count}"
    puts "  Errors: #{error_count}"
    puts "=" * 50
  end
end

