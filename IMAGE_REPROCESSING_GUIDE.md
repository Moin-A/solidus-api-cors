# Image Reprocessing Guide

Guide for reducing image sizes by reprocessing existing images with compression.

---

## Quick Start: Rails Console

### Reprocess a Single Image

```ruby
# In Rails console: rails console

# Find an image
image = Spree::Image.first

# Check current size
image.attachment.blob.byte_size / 1024.0 / 1024.0  # Size in MB

# Reprocess all variants (this will create new compressed versions)
image.attachment.variant_records.each(&:destroy) if image.attachment.respond_to?(:variant_records)

# Trigger variant creation for each style
Spree::Config.product_image_styles.keys.each do |style|
  image.attachment(style)  # This creates the variant with compression
end
```

### Reprocess All Images

```ruby
# In Rails console: rails console

processed = 0
errors = 0

Spree::Image.find_each do |image|
  begin
    if image.attachment.attached?
      puts "Processing image ##{image.id}..."
      
      # Purge existing variants
      image.attachment.variant_records.each(&:destroy) if image.attachment.respond_to?(:variant_records)
      
      # Create new compressed variants
      Spree::Config.product_image_styles.keys.each do |style|
        image.attachment(style)
      end
      
      processed += 1
      puts "✓ Completed image ##{image.id}"
    end
  rescue => e
    errors += 1
    puts "✗ Error: #{e.message}"
  end
end

puts "Processed: #{processed}, Errors: #{errors}"
```

### Reprocess Images in Batches (Recommended for Large Sets)

```ruby
# In Rails console: rails console

batch_size = 10
processed = 0
errors = 0

Spree::Image.find_in_batches(batch_size: batch_size) do |batch|
  batch.each do |image|
    begin
      if image.attachment.attached?
        puts "Processing image ##{image.id}..."
        
        # Purge existing variants
        image.attachment.variant_records.each(&:destroy) if image.attachment.respond_to?(:variant_records)
        
        # Create new compressed variants
        Spree::Config.product_image_styles.keys.each do |style|
          image.attachment(style)
        end
        
        processed += 1
      end
    rescue => e
      errors += 1
      puts "✗ Error on image ##{image.id}: #{e.message}"
    end
  end
  
  puts "Batch complete. Processed: #{processed}, Errors: #{errors}"
end
```

---

## Check Image Sizes

### Check Size of a Single Image

```ruby
image = Spree::Image.first

if image.attachment.attached?
  blob = image.attachment.blob
  size_mb = blob.byte_size / 1024.0 / 1024.0
  puts "Image: #{blob.filename}"
  puts "Size: #{size_mb.round(2)} MB"
  puts "Content type: #{blob.content_type}"
end
```

### Check Total Size of All Images

```ruby
total_size = 0
image_count = 0

Spree::Image.find_each do |image|
  if image.attachment.attached?
    begin
      size_mb = image.attachment.blob.byte_size / 1024.0 / 1024.0
      total_size += size_mb
      image_count += 1
    rescue => e
      puts "Error reading image ##{image.id}: #{e.message}"
    end
  end
end

puts "Total images: #{image_count}"
puts "Total size: #{total_size.round(2)} MB"
puts "Average size: #{(total_size / image_count).round(2)} MB" if image_count > 0
```

---

## Using the Rake Task

Alternatively, you can use the rake task:

```bash
# Reprocess all images
rails images:reprocess

# Check image statistics
rails images:stats
```

---

## Configuration

### Adjust Image Quality

The compression quality is controlled by the `IMAGE_QUALITY` environment variable (default: 85).

```ruby
# In config/initializers/spree.rb or environment
# Lower = smaller files but lower quality
# Higher = better quality but larger files
# Range: 1-100

ENV['IMAGE_QUALITY'] = '75'  # More compression
ENV['IMAGE_QUALITY'] = '90'  # Less compression
```

### Adjust Image Dimensions

Edit `config/initializers/spree.rb`:

```ruby
Spree.config do |config|
  config.product_image_styles = {
    mini: '48x48>',
    small: '300x300>',      # Adjust as needed
    product: '600x600>',    # Adjust as needed
    large: '1000x1000>'    # Adjust as needed
  }
end
```

---

## How It Works

1. **New Images**: Automatically compressed when variants are created
2. **Existing Images**: Use the console commands or rake task to reprocess
3. **Compression Settings**:
   - Quality: 85% (configurable via `IMAGE_QUALITY` env var)
   - Strip metadata: Enabled (removes EXIF data)
   - Dimensions: Reduced from defaults (see config)

---

## Notes

- Original images are not modified - only variants are regenerated
- Old variants are purged before creating new ones
- Processing happens on-demand (when variants are requested)
- CloudFront will cache the new compressed versions

---

**Created:** January 2025  
**Related Files:** `app/models/concerns/spree/active_storage_adapter/attachment.rb`, `config/initializers/spree.rb`, `lib/tasks/reprocess_images.rake`



