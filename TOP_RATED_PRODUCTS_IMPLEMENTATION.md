# Top Rated Products Implementation Guide

This document explains how to implement and use the Top Rated Products system in your Solidus application.

## Overview

The Top Rated Products system allows you to:
- Store product ratings (1-5 stars) from users
- Calculate average ratings per product
- Query top-rated products dynamically
- Display ratings in your API responses

## Database Schema

### `spree_ratings` Table

```ruby
create_table :spree_ratings do |t|
  t.references :product, null: false, foreign_key: { to_table: :spree_products }
  t.references :user, null: false, foreign_key: { to_table: :spree_users }
  t.integer :rating, null: false, default: 0  # 1-5 stars
  t.text :review
  t.boolean :approved, default: false, null: false
  t.timestamps
end
```

**Constraints:**
- Rating must be between 1 and 5
- One rating per user per product (unique constraint)
- Indexed on `[product_id, user_id]` for uniqueness
- Indexed on `[product_id, approved]` for faster queries

## Models

### Spree::Rating

**Location:** `app/models/spree/rating.rb`

**Associations:**
- `belongs_to :product`
- `belongs_to :user`

**Validations:**
- `rating`: Must be between 1 and 5
- `product_id`: Unique per user (prevents duplicate ratings)
- `review`: Maximum 1000 characters

**Scopes:**
- `approved` - Only approved ratings
- `pending` - Pending approval ratings
- `recent` - Ordered by creation date

**Class Methods:**
- `average_for_product(product)` - Calculate average rating for a product
- `count_for_product(product)` - Count ratings for a product

### Spree::Product (Extended)

**New Associations:**
```ruby
has_many :ratings, class_name: 'Spree::Rating', dependent: :destroy
has_many :approved_ratings, -> { approved }, class_name: 'Spree::Rating'
```

**New Scope:**
```ruby
scope :top_rated, ->(limit = 10, min_ratings = 3) {
  left_joins(:approved_ratings)
    .group('spree_products.id')
    .having('COUNT(spree_ratings.id) >= ?', min_ratings)
    .order('AVG(spree_ratings.rating) DESC')
    .limit(limit)
}
```

**New Instance Methods:**
- `average_rating` - Returns average rating (rounded to 1 decimal)
- `ratings_count` - Returns count of approved ratings
- `has_ratings?` - Returns true if product has any ratings

## API Endpoints

### Get Top Rated Products

**Endpoint:** `GET /api/products/top_rated`

**Parameters:**
- `limit` (optional, default: 10) - Number of products to return
- `min_ratings` (optional, default: 3) - Minimum number of ratings required

**Example Request:**
```bash
GET /api/products/top_rated?limit=12&min_ratings=3
```

**Example Response:**
```json
{
  "products": [
    {
      "id": 1,
      "name": "Demons Souls",
      "average_rating": 4.8,
      "ratings_count": 125,
      "master": {
        "default_price": {
          "amount": "1699.0",
          "currency": "USD"
        }
      },
      "images": [...],
      "taxons": [...]
    },
    ...
  ]
}
```

### Product Index (Updated)

The `GET /api/products` endpoint now includes rating information:

```json
{
  "products": [
    {
      "id": 1,
      "name": "Product Name",
      "average_rating": 4.5,
      "ratings_count": 42,
      ...
    }
  ]
}
```

### Product Show (Updated)

The `GET /api/products/:id` endpoint now includes rating information:

```json
{
  "id": 1,
  "name": "Product Name",
  "average_rating": 4.5,
  "ratings_count": 42,
  ...
}
```

## Usage Examples

### 1. Creating a Rating

```ruby
# In your controller or service
product = Spree::Product.find(1)
user = current_user

rating = Spree::Rating.create!(
  product: product,
  user: user,
  rating: 5,
  review: "Excellent product! Highly recommended.",
  approved: true  # Set to false if you want admin approval
)
```

### 2. Querying Top Rated Products

```ruby
# Get top 10 products with at least 3 ratings
top_products = Spree::Product.top_rated(10, 3)

# Get top 5 products with at least 5 ratings
top_products = Spree::Product.top_rated(5, 5)

# With additional scopes
top_available = Spree::Product.available.top_rated(10, 3)
```

### 3. Getting Product Rating Info

```ruby
product = Spree::Product.find(1)

product.average_rating  # => 4.5
product.ratings_count   # => 42
product.has_ratings?    # => true
```

### 4. Frontend Integration

**React/Next.js Example:**
```javascript
// Fetch top rated products
const response = await fetch('/api/products/top_rated?limit=12&min_ratings=3');
const { products } = await response.json();

// Display products
products.map(product => (
  <div key={product.id}>
    <h3>{product.name}</h3>
    <div>
      ⭐ {product.average_rating} ({product.ratings_count} reviews)
    </div>
    <p>${product.master.default_price.amount}</p>
  </div>
))
```

**Vue.js Example:**
```javascript
// In your component
async fetchTopRated() {
  const response = await fetch('/api/products/top_rated?limit=12');
  const { products } = await response.json();
  this.topRatedProducts = products;
}
```

## Migration Steps

1. **Run the migration:**
   ```bash
   bin/rails db:migrate
   ```

2. **Seed some sample ratings (optional):**
   ```ruby
   # In rails console
   product = Spree::Product.first
   user = Spree::User.first
   
   Spree::Rating.create!(
     product: product,
     user: user,
     rating: 5,
     review: "Great product!",
     approved: true
   )
   ```

3. **Test the API:**
   ```bash
   curl http://localhost:3000/api/products/top_rated?limit=10
   ```

## Caching

The `top_rated` endpoint uses Rails cache with a 1-hour expiration:

```ruby
cache_key = "top_rated_products_limit_#{limit}_min_#{min_ratings}"
@products = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  # Query logic
end
```

**To clear cache when ratings change:**
```ruby
# In your Rating model or callback
after_save :clear_product_rating_cache

def clear_product_rating_cache
  Rails.cache.delete_matched("top_rated_products_*")
end
```

## Admin Approval Workflow

If you want to require admin approval for ratings:

1. Set `approved: false` when creating ratings
2. Create an admin interface to approve ratings
3. Only query `approved_ratings` in your scopes

**Example:**
```ruby
# In admin controller
def approve_rating
  @rating = Spree::Rating.find(params[:id])
  @rating.update(approved: true)
  # Clear cache
  Rails.cache.delete_matched("top_rated_products_*")
end
```

## Performance Considerations

1. **Indexes:** The migration includes indexes for fast queries
2. **Caching:** Top rated products are cached for 1 hour
3. **Eager Loading:** The API includes necessary associations
4. **Minimum Ratings:** The `min_ratings` parameter prevents products with few ratings from appearing

## Customization

### Change Rating Scale

To use a different scale (e.g., 1-10), update:
1. Migration: Change check constraint
2. Rating model: Update validation
3. Product model: Update `average_rating` rounding if needed

### Add Rating Categories

To add categories (e.g., "Quality", "Price", "Shipping"):

1. Create a migration:
   ```ruby
   add_column :spree_ratings, :category, :string
   ```

2. Update the model:
   ```ruby
   validates :category, inclusion: { in: %w[quality price shipping] }
   ```

3. Update scopes to filter by category

## Troubleshooting

**Issue:** No products returned from `top_rated`
- **Solution:** Ensure products have at least `min_ratings` approved ratings

**Issue:** Ratings not showing in API
- **Solution:** Check that ratings are `approved: true`

**Issue:** Duplicate ratings error
- **Solution:** This is expected - one rating per user per product

## Next Steps

1. Create a ratings controller for users to submit ratings
2. Add admin interface for approving ratings
3. Add email notifications when products are rated
4. Implement rating analytics dashboard
5. Add "Helpful" votes for reviews





