# Run these commands in production Rails console (kamal app exec "bin/rails console")
# Or SSH into your server and run: docker exec -it <your-app-container> bin/rails console

# Step 1: Create the index with the correct mappings
Spree::Product.__elasticsearch__.create_index!(force: true)

# Step 2: Import all products into Elasticsearch
# This will index all existing products
Spree::Product.import

# Step 3: Verify the index was created and has documents
Spree::Product.__elasticsearch__.refresh_index!
puts "Total products indexed: #{Spree::Product.__elasticsearch__.search({ query: { match_all: {} } }).total}"

