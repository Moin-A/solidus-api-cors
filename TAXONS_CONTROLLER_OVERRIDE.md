# Spree::Api::TaxonsController Override

## Overview
This file documents the `Spree::Api::TaxonsController` that has been placed at the application level to allow customization of taxon-related API endpoints.

## File Location
```
app/controllers/spree/api/taxons_controller.rb
```

## Why Override?
By placing this controller in your application, it overrides the default implementation from the `solidus_api` gem. This allows you to:
- Customize response formats
- Add additional endpoints
- Modify query logic
- Add custom authentication/authorization
- Enhance performance with caching

## Original Source
This controller was copied from:
```
solidus_api-4.5.1/app/controllers/spree/api/taxons_controller.rb
```

## Available Endpoints

### 1. GET /api/taxons
**Purpose**: List all taxons or filter by taxonomy

**Query Parameters**:
- `taxonomy_id` - Filter taxons by taxonomy
- `ids` - Comma-separated list of taxon IDs
- `q` - Ransack search params
- `without_children` - Exclude child taxons
- `page` - Page number for pagination
- `per_page` - Items per page (default: 500)

**Examples**:
```bash
# Get all taxons
curl http://localhost:3001/api/taxons

# Get taxons for a specific taxonomy
curl http://localhost:3001/api/taxons?taxonomy_id=1

# Get specific taxons by IDs
curl http://localhost:3001/api/taxons?ids=1,2,3

# Get taxons without children
curl http://localhost:3001/api/taxons?without_children=true
```

### 2. GET /api/taxons/:id
**Purpose**: Get a single taxon by ID

**Example**:
```bash
curl http://localhost:3001/api/taxons/14
```

### 3. POST /api/taxonomies/:taxonomy_id/taxons
**Purpose**: Create a new taxon under a taxonomy

**Parameters**:
- `taxon[name]` - Name of the taxon (required)
- `taxon[parent_id]` - Parent taxon ID (optional)
- `taxon[permalink]` - URL-friendly permalink (optional)
- `taxon[description]` - Description (optional)

**Example**:
```bash
curl -X POST http://localhost:3001/api/taxonomies/1/taxons \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "taxon": {
      "name": "New Category",
      "parent_id": 1
    }
  }'
```

### 4. PUT /api/taxons/:id
**Purpose**: Update an existing taxon

**Example**:
```bash
curl -X PUT http://localhost:3001/api/taxons/14 \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "taxon": {
      "name": "Updated Fashion",
      "description": "Latest fashion items"
    }
  }'
```

### 5. DELETE /api/taxons/:id
**Purpose**: Delete a taxon

**Example**:
```bash
curl -X DELETE http://localhost:3001/api/taxons/14 \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### 6. GET /api/taxons/:id/products
**Purpose**: Get all products within a taxon

**Query Parameters**:
- `simple` - Return simplified product data
- `q` - Ransack search params
- `page` - Page number
- `per_page` - Items per page

**Example**:
```bash
# Get all products in Fashion taxon
curl http://localhost:3001/api/taxons/14/products

# Get simplified product list
curl http://localhost:3001/api/taxons/14/products?simple=true
```

## Key Methods

### Public Methods

#### `index`
Lists taxons based on filters. Supports:
- Taxonomy-based filtering
- ID-based filtering
- Ransack search
- Pagination
- Parent preloading for performance

#### `show`
Returns a single taxon with all details.

#### `create`
Creates a new taxon. Requires:
- `taxonomy_id` parameter
- Valid taxon params
- Authorization to create taxons

#### `update`
Updates an existing taxon. Requires authorization.

#### `destroy`
Deletes a taxon. Requires authorization.

#### `products`
Returns products within a taxon, sorted by their classification position.

### Private Methods

#### `default_per_page`
Sets pagination to 500 items per page by default.

#### `taxonomy`
Finds the taxonomy based on `taxonomy_id` parameter.

#### `taxon`
Finds a specific taxon within a taxonomy.

#### `taxon_params`
Strong parameters for taxon attributes.

#### `preload_taxon_parents`
Optimizes queries by preloading taxon parent relationships.

## Customization Examples

### Example 1: Add Caching to Index
```ruby
def index
  cache_key = "taxons_index_#{params[:taxonomy_id]}_#{params[:page]}"
  @taxons = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    # ... existing logic
  end
  respond_with(@taxons)
end
```

### Example 2: Add Custom Response Format
```ruby
def show
  @taxon = taxon
  
  # Add custom fields to response
  custom_response = @taxon.as_json.merge(
    product_count: @taxon.products.count,
    child_count: @taxon.children.count,
    full_path: @taxon.pretty_name
  )
  
  render json: custom_response
end
```

### Example 3: Add Search Endpoint
```ruby
def search
  @taxons = Spree::Taxon
    .where('name ILIKE ?', "%#{params[:q]}%")
    .limit(10)
  
  render json: @taxons
end
```

## Integration with Products API

The taxons controller works seamlessly with the products API:

```ruby
# Get Fashion taxon details
taxon = GET /api/taxons/14

# Get all Fashion products
products = GET /api/taxons/14/products

# Or filter products by taxon
products = GET /api/products?taxon_id=14
```

## Performance Considerations

1. **Pagination**: Default is 500 items, which is quite high
2. **Parent Preloading**: Uses `preload_taxon_parents` to avoid N+1 queries
3. **Includes**: Loads children when needed
4. **Ransack**: Allows complex filtering

## Security

- Uses CanCan for authorization
- Requires authentication for create/update/delete operations
- Read operations are accessible based on ability rules

## Testing

### Test if override is working:
```bash
# This should use your custom controller
curl http://localhost:3001/api/taxons?taxonomy_id=1

# Check the controller being used
rails runner "puts Spree::Api::TaxonsController.ancestors"
```

### Test Fashion taxon:
```bash
# Get Fashion taxon
curl http://localhost:3001/api/taxons/14

# Get Fashion products
curl http://localhost:3001/api/taxons/14/products
```

## Next Steps

Now that you have the controller at the application level, you can:

1. **Add custom endpoints**
2. **Modify response formats**
3. **Add caching strategies**
4. **Implement custom search**
5. **Add analytics tracking**
6. **Customize authorization rules**

## Notes

- Changes to this file will take effect immediately (in development mode)
- The controller inherits from `Spree::Api::BaseController`
- Uses Solidus responders for consistent API responses
- Supports all standard Solidus taxon operations
