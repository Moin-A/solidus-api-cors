namespace :sample do
  desc "Show all available sample tasks"
  task help: :environment do
    puts "Available sample tasks:"
    puts "  rails sample:list_sample_images     - List all sample images"
    puts "  rails sample:fashion_products       - Create fashion products with sample images"
    puts "  rails sample:clean_fashion_products - Clean up fashion products (use with caution!)"
    puts "  rails sample:help                   - Show this help"
  end

  desc "Create fashion products with sample images from db/sample_images"
  task fashion_products: :environment do
    puts "Creating fashion products with sample images..."
    
    # Find or create Fashion taxon
    fashion_taxon = Spree::Taxon.find_or_create_by(name: 'Fashion') do |taxon|
      taxon.taxonomy = Spree::Taxonomy.find_or_create_by(name: 'Categories')
      taxon.parent = Spree::Taxon.find_by(name: 'Categories')
      taxon.save!
    end
    
    # Find shipping category
    shipping_category = Spree::ShippingCategory.find_or_create_by(name: 'Default')
    
    # Sample images directory
    sample_images_dir = Rails.root.join('db', 'sample_images')
    
    # Product data mapping to sample images
    products_data = [
      {
        name: 'Premium Headphones',
        price: 199.99,
        description: 'High-quality wireless headphones with noise cancellation',
        image_file: 'Black Headphones Closeup.jpg'
      },
      {
        name: 'Wireless Earbuds',
        price: 149.99,
        description: 'Compact wireless earbuds with excellent sound quality',
        image_file: 'Black Wireless Bluetooth Earbuds.jpg'
      },
      {
        name: 'Professional Headphones',
        price: 179.99,
        description: 'Professional-grade headphones for music and gaming',
        image_file: 'headphones.jpg'
      },
      {
        name: 'Vintage Camera',
        price: 299.99,
        description: 'Classic vintage camera with film rolls - perfect for photography enthusiasts',
        image_file: 'Vintage Camera with Film Rolls.jpg'
      },
      {
        name: 'Portable Speakers',
        price: 89.99,
        description: 'Wireless portable speakers with excellent sound quality',
        image_file: 'Wireless Portable Speakers.jpg'
      }
    ]
    
    created_count = 0
    
    products_data.each do |data|
      begin
        puts "Creating product: #{data[:name]}..."
        
        # Check if product already exists
        existing_product = Spree::Product.find_by(name: data[:name])
        if existing_product
          puts "  ⚠️  Product '#{data[:name]}' already exists, skipping..."
          next
        end
        
        # Create product
        product = Spree::Product.create!(
          name: data[:name],
          description: data[:description],
          price: data[:price],
          shipping_category: shipping_category,
          available_on: Time.current,
          slug: data[:name].parameterize
        )
        
        # Add to Fashion taxon
        product.taxons << fashion_taxon unless product.taxons.include?(fashion_taxon)
        
        # Add image if file exists
        image_path = sample_images_dir.join(data[:image_file])
        if File.exist?(image_path)
          begin
            File.open(image_path, 'rb') do |file|
              product.images.create!(
                attachment: {
                  io: file,
                  filename: data[:image_file],
                  content_type: 'image/jpeg'
                }
              )
            end
            puts "  ✓ Product created with image: #{data[:image_file]}"
          rescue => e
            puts "  ⚠️  Product created but image failed: #{e.message}"
          end
        else
          puts "  ⚠️  Product created but image file not found: #{data[:image_file]}"
        end
        
        created_count += 1
        
      rescue => e
        puts "  ✗ Error creating product '#{data[:name]}': #{e.message}"
      end
    end
    
    puts "\n" + "="*60
    puts "Summary:"
    puts "  Created: #{created_count} new products"
    puts "  Total Fashion products: #{fashion_taxon.products.count}"
    puts "  Sample images directory: #{sample_images_dir}"
    puts "="*60
  end
  
  desc "List all sample images in db/sample_images"
  task list_sample_images: :environment do
    sample_images_dir = Rails.root.join('db', 'sample_images')
    
    puts "Sample images in #{sample_images_dir}:"
    puts "-" * 50
    
    if Dir.exist?(sample_images_dir)
      Dir.glob(File.join(sample_images_dir, '*.{jpg,jpeg,png,gif}')).each do |file|
        filename = File.basename(file)
        size = File.size(file)
        puts "  #{filename} (#{size} bytes)"
      end
    else
      puts "  Directory not found: #{sample_images_dir}"
    end
  end
  
  desc "Clean up sample fashion products (use with caution!)"
  task clean_fashion_products: :environment do
    puts "⚠️  WARNING: This will delete all products with 'Fashion' taxon!"
    print "Are you sure? Type 'yes' to continue: "
    
    confirmation = STDIN.gets.chomp
    if confirmation.downcase == 'yes'
      fashion_taxon = Spree::Taxon.find_by(name: 'Fashion')
      if fashion_taxon
        count = fashion_taxon.products.count
        fashion_taxon.products.destroy_all
        puts "✓ Deleted #{count} fashion products"
      else
        puts "No Fashion taxon found"
      end
    else
      puts "Operation cancelled"
    end
  end
end
