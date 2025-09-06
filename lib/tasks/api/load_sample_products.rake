# lib/tasks/solidus_sample_data.rake
namespace :solidus do
    desc "Add sample electronics products"
    task load_electronics_products: :environment do
      puts "Loading data..."
      load_sample_products
    end
  
    private
  
    def load_sample_products
      tax_category = Spree::TaxCategory.first
      shipping_category = Spree::ShippingCategory.first
  
      products_data = [
        {
          name: "Black Headphones Closeup",
          price: 29.99,
          description: "High-quality black headphones with superior sound quality.",
          sku: "HEADPHONES-001",
          slug: "black-headphones-closeup"
        },
        {
          name: "Black Wireless Bluetooth Earbuds",
          price: 49.99,
          description: "Wireless bluetooth earbuds with noise cancellation.",
          sku: "EARBUDS-001",
          slug: "black-wireless-bluetooth-earbuds"
        },
        {
          name: "Vintage Camera with Film Rolls",
          price: 79.99,
          description: "Classic vintage camera with film rolls for photography enthusiasts.",
          sku: "CAMERA-001",
          slug: "vintage-camera-and-rolls-of-film"
        },
        {
          name: "Wireless Portable Speakers",
          price: 89.99,
          description: "Portable wireless speakers with excellent bass and clarity.",
          sku: "SPEAKERS-001",
          slug: "wireless-portable-speakers"
        }
      ]
  
      # Create taxonomy and Electronics category
      taxonomy = Spree::Taxonomy.find_or_create_by(name: "Categories")
  
      electronics = Spree::Taxon.find_or_create_by(
        name: "Electronics",
        taxonomy: taxonomy,
        parent: taxonomy.root
      ) do |t|
        t.permalink = "electronics"
        t.description = "Electronic devices and gadgets"
      end
  
      products_data.each do |product_data|
        puts "Creating product: #{product_data[:name]}"
  
        product = Spree::Product.new(
          name: product_data[:name],
          description: product_data[:description],
          slug: product_data[:slug],
          tax_category: tax_category,
          shipping_category: shipping_category,
          available_on: Time.current
        )
  
        # Assign random price to master variant
        master = product.master
        product.master.price = [100, 200, 300, 148, 345].sample
        product.master.save!
        product.master.stock_items.update_all(count_on_hand: 10)
  
        # Save product (this creates master variant automatically)
        product.save!
  
        # Assign to Electronics category if not already assigned
        unless product.taxons.include?(electronics)
          product.taxons << electronics
          puts "Assigned #{product.name} to Electronics category"
        end
  
        # Update master variant dimensions
        master.update!(
          weight: 1.0,
          height: 10.0,
          width: 10.0,
          depth: 10.0
        )
  
        puts "Created product: #{product.name} (#{master.sku}) - $#{master.price}"
  
        # Attach product image
        load_product_images(product)
      end
    end
  
    def load_product_images(product)
      puts "Loading product images..."
      image_base_path = Rails.root.join("db", "sample_images")
      image_file = image_base_path.join("#{product.name}.jpg")
  
      puts "Attaching image to #{product.name}"
      image = Spree::Image.new
      image.viewable = product.master
      image.attachment.attach(
        io: File.open(image_file),
        filename: File.basename(image_file),
        content_type: "image/jpg"
      )
      image.save!
      puts "Image attached successfully to #{product.name}"
    end
  end
  