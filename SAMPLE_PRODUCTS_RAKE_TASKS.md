# Sample Fashion Products Rake Tasks

This document explains how to use the rake tasks for creating fashion products with sample images.

## Available Tasks

### 1. List Sample Images
```bash
rails sample:list_sample_images
```
Lists all available sample images in the `db/sample_images` directory with their file sizes.

### 2. Create Fashion Products
```bash
rails sample:fashion_products
```
Creates fashion products using the sample images from `db/sample_images`. This task will:

- Find or create the "Fashion" taxon under "Categories"
- Create products with appropriate names, descriptions, and prices
- Attach the corresponding sample images
- Assign products to the Fashion taxon
- Skip products that already exist (prevents duplicates)

**Products Created:**
- Premium Headphones ($199.99) - Black Headphones Closeup.jpg
- Wireless Earbuds ($149.99) - Black Wireless Bluetooth Earbuds.jpg
- Professional Headphones ($179.99) - headphones.jpg
- Vintage Camera ($299.99) - Vintage Camera with Film Rolls.jpg
- Portable Speakers ($89.99) - Wireless Portable Speakers.jpg

### 3. Clean Fashion Products
```bash
rails sample:clean_fashion_products
```
⚠️ **WARNING**: This will delete ALL products assigned to the "Fashion" taxon!

The task will ask for confirmation before proceeding.

### 4. Show Help
```bash
rails sample:help
```
Displays all available sample tasks with descriptions.

## File Structure

```
db/sample_images/
├── Black Headphones Closeup.jpg
├── Black Wireless Bluetooth Earbuds.jpg
├── headphones.jpg
├── Vintage Camera with Film Rolls.jpg
└── Wireless Portable Speakers.jpg
```

## Usage Examples

### Create all fashion products:
```bash
rails sample:fashion_products
```

### Check what images are available:
```bash
rails sample:list_sample_images
```

### See all available tasks:
```bash
rails sample:help
```

### Clean up and start fresh:
```bash
rails sample:clean_fashion_products
rails sample:fashion_products
```

## Adding New Sample Images

To add new sample images:

1. Place image files in `db/sample_images/`
2. Update the `products_data` array in `lib/tasks/sample_fashion_products.rake`
3. Add a new entry with:
   - `name`: Product name
   - `price`: Product price
   - `description`: Product description
   - `image_file`: Filename in sample_images directory

Example:
```ruby
{
  name: 'New Product',
  price: 99.99,
  description: 'Description of the new product',
  image_file: 'new_product_image.jpg'
}
```

## Notes

- Images should be in JPG, JPEG, PNG, or GIF format
- The rake task automatically handles file uploads and image attachments
- Products are created with "Default" shipping category
- All products are set as available immediately
- The task prevents duplicate products by checking existing names
- Images are attached using Active Storage

## Troubleshooting

### "Image file not found" error:
- Check that the image file exists in `db/sample_images/`
- Verify the filename matches exactly (case-sensitive)
- Ensure the file is a valid image format

### "Product already exists" warning:
- This is normal behavior to prevent duplicates
- Use `rails sample:clean_fashion_products` to remove existing products first

### Permission errors:
- Ensure the Rails application has read access to `db/sample_images/`
- Check file permissions on the sample images directory
