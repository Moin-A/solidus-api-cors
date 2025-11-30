# frozen_string_literal: true

namespace :images do
  desc "Reprocess all product images with compression to reduce file sizes"
  task reprocess: :environment do
    puts "Starting image reprocessing..."
    puts "This will regenerate all image variants with compression settings."
    puts "Original images will not be modified.\n\n"
    
    total_images = Spree::Image.count
    processed = 0
    errors = 0
    
    Spree::Image.find_each do |image|
      begin
        if image.attachment.attached?
          puts "Processing image ##{image.id} (#{image.attachment.filename})..."
          
          # Force regeneration of all variants by purging existing variants
          # This will trigger new variants to be created with compression
          image.attachment.variant_records.each(&:destroy) if image.attachment.respond_to?(:variant_records)
          
          # Trigger variant creation for each style
          styles = Spree::Config.product_image_styles.keys
          styles.each do |style|
            begin
              image.attachment(style) # This triggers variant creation
              puts "  ✓ Generated #{style} variant"
            rescue => e
              puts "  ⚠️  Failed to generate #{style} variant: #{e.message}"
            end
          end
          
          processed += 1
          puts "  ✓ Completed image ##{image.id}\n"
        else
          puts "  ⚠️  Image ##{image.id} has no attachment, skipping\n"
        end
      rescue => e
        errors += 1
        puts "  ✗ Error processing image ##{image.id}: #{e.message}\n"
        Rails.logger.error("Image reprocessing error for image ##{image.id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      end
    end
    
    puts "\n" + "="*60
    puts "Reprocessing Complete!"
    puts "  Total images: #{total_images}"
    puts "  Processed: #{processed}"
    puts "  Errors: #{errors}"
    puts "="*60
  end
  
  desc "Show image size statistics"
  task stats: :environment do
    puts "Image Size Statistics\n"
    puts "="*60
    
    total_size = 0
    image_count = 0
    
    Spree::Image.find_each do |image|
      if image.attachment.attached?
        begin
          blob = image.attachment.blob
          size_mb = blob.byte_size / 1024.0 / 1024.0
          total_size += size_mb
          image_count += 1
          
          puts "Image ##{image.id}: #{blob.filename} - #{size_mb.round(2)} MB"
        rescue => e
          puts "Image ##{image.id}: Error reading size - #{e.message}"
        end
      end
    end
    
    puts "\n" + "="*60
    puts "Summary:"
    puts "  Total images: #{image_count}"
    puts "  Total size: #{total_size.round(2)} MB"
    puts "  Average size: #{(total_size / image_count).round(2)} MB" if image_count > 0
    puts "="*60
  end
end

