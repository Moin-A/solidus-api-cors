# Active Storage Quick Guide

## Overview

Active Storage is Rails' built-in framework for handling file uploads and attachments. This guide explains how we've customized it in our Solidus application to work seamlessly across different environments.

## Table of Contents
1. [Understanding the URL Methods](#understanding-the-url-methods)
2. [Architecture Overview](#architecture-overview)
3. [Custom `attachment_url` Implementation](#custom-attachment_url-implementation)
4. [Environment-Specific Behavior](#environment-specific-behavior)
5. [Usage Examples](#usage-examples)
6. [Troubleshooting](#troubleshooting)

---

## Understanding the URL Methods

Active Storage provides several methods to get URLs for attachments. Understanding the differences is crucial:

### 1. **`attachment.blob.key`**
```ruby
taxon.icon.blob.key
# => "696msb7j0sp6zytfuym7esfwso3y.webp"
```
- Returns just the storage key (filename in storage)
- No URL, just the identifier
- Useful for direct storage operations

### 2. **`attachment.service_url`**
```ruby
taxon.icon.service_url
# => "https://s3.amazonaws.com/bucket-name/696msb7j0sp6zytfuym7esfwso3y.webp?signature=..."
```
- Direct URL from storage service (S3, GCS, etc.)
- Often includes temporary signatures
- Bypasses Rails entirely
- ⚠️ Problem: Exposes raw S3 URLs (slow, no CDN)

### 3. **`url_for(attachment)`**
```ruby
url_for(taxon.icon)
# => "/rails/active_storage/blobs/redirect/..."
```
- Rails routing helper
- ⚠️ Problem: Only works in controller/view context
- Won't work in models, console, or background jobs
- Needs `default_url_options[:host]` to be set

### 4. **`attachment.url(style)`**
```ruby
taxon.icon.url(:mini)
# => "/rails/active_storage/representations/..."
```
- Spree/Solidus method for styled/resized images
- Supports transformations (`:mini`, `:normal`, etc.)
- Returns path, not full URL
- Can return fallback: `"noimage/mini.png"`

### 5. **`attachment_url`** ⭐ (Recommended)
```ruby
taxon.attachment_url
# => "https://d3687nk8qb4e0v.cloudfront.net/696msb7j0sp6zytfuym7esfwso3y.webp"
```
- **Custom method** we've implemented
- Environment-aware (dev vs production)
- Works everywhere (models, controllers, console, jobs)
- Automatically uses CloudFront in production
- Handles nil attachments gracefully

---

## Architecture Overview

### The Problem
Different environments need different URL strategies:
- **Development:** Files served through Rails
- **Staging:** Files on S3 or local storage
- **Production:** Files served from CloudFront CDN (faster, cached globally)

### The Solution
Create a **single, smart method** (`attachment_url`) that adapts based on environment.

```
┌─────────────────────────────────────────────┐
│          taxon.attachment_url               │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │ Environment?   │
         └────────┬───────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
    PRODUCTION        DEVELOPMENT
         │                 │
         ▼                 ▼
   CloudFront         Rails Helper
   Override           (Default)
         │                 │
         ▼                 ▼
   CDN URL          Rails URL
```

---

## Custom `attachment_url` Implementation

### Base Implementation (Development)

Located in: `app/models/concerns/spree/active_storage_adapter.rb`

```ruby
def attachment_url
  Rails.application.routes.url_helpers.rails_blob_url(
    attachment,
    host: "thestorefront.co.in",
    only_path: false,
  )
end
```

Returns: `https://thestorefront.co.in/rails/active_storage/blobs/redirect/...`

### Production Override (CloudFront)

Located in: `config/initializers/active_storage_cloudfront.rb`

```ruby
if Rails.env.production?
  Rails.application.config.to_prepare do
    Spree::ActiveStorageAdapter.module_eval do
      def attachment_url
        return nil unless attachment.attached?
        
        # Use CloudFront URL directly
        cloudfront_base = ENV.fetch("CLOUDFRONT_URL", "https://d3687nk8qb4e0v.cloudfront.net").chomp("/")
        "#{cloudfront_base}/#{attachment.blob.key}"
      end
    end
  end
end
```

Returns: `https://d3687nk8qb4e0v.cloudfront.net/696msb7j0sp6zytfuym7esfwso3y.webp`

### Why This Works

1. **Monkey Patching with `module_eval`**
   - `Spree::ActiveStorageAdapter` is a MODULE (not a class)
   - We redefine `attachment_url` method at runtime
   - In production, the CloudFront version overwrites the default

2. **Using `to_prepare` hook**
   - Runs after code loads/reloads
   - In development: runs on every request (survives code reloads)
   - In production: runs once on startup (no performance penalty)

---

## Environment-Specific Behavior

### Development Environment
```ruby
taxon = Spree::Taxon.find(2)
taxon.attachment_url
# => "https://thestorefront.co.in/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsib..."
```

**Request Flow:**
1. Browser requests the URL
2. Rails controller receives request
3. Rails redirects to actual file location
4. File served from local disk or S3

### Production Environment
```ruby
taxon = Spree::Taxon.find(2)
taxon.attachment_url
# => "https://d3687nk8qb4e0v.cloudfront.net/696msb7j0sp6zytfuym7esfwso3y.webp"
```

**Request Flow:**
1. Browser requests CloudFront URL directly
2. CloudFront serves from cache (if available)
3. If not cached, CloudFront fetches from S3
4. File served with global CDN performance

**Benefits:**
- ⚡ Faster load times (CDN edge locations)
- 📉 Reduced server load (no Rails processing)
- 💰 Lower bandwidth costs
- 🌍 Better global performance

---

## Usage Examples

### In Controllers

```ruby
# categories_controller.rb
def taxons
  @category = Spree::Taxon.find_by(permalink: "categories/#{params[:id]}")
  
  render json: @category.as_json.merge(
    attachment_url: @category.attachment_url
  )
end
```

### In Models

```ruby
# In any model with Active Storage attachment
class Spree::Taxon < Spree::Base
  # icon is attached via ActiveStorageAdapter
  
  def icon_data
    {
      filename: icon.filename,
      url: attachment_url,  # Works in model!
      attached: icon.attached?
    }
  end
end
```

### In Views

```erb
<% if @taxon.icon.attached? %>
  <%= image_tag @taxon.attachment_url, alt: @taxon.name %>
<% end %>
```

### In Background Jobs

```ruby
class TaxonExportJob < ApplicationJob
  def perform(taxon_id)
    taxon = Spree::Taxon.find(taxon_id)
    
    # attachment_url works in jobs too!
    data = {
      name: taxon.name,
      icon_url: taxon.attachment_url
    }
    
    # Export data...
  end
end
```

### In Rails Console

```ruby
# Console commands that work:
taxon = Spree::Taxon.find(2)

# ✅ Works everywhere
taxon.attachment_url

# ✅ Check if attached
taxon.icon.attached?

# ✅ Get filename
taxon.icon.filename

# ✅ Get blob key
taxon.icon.blob.key

# ❌ Won't work (needs controller context)
url_for(taxon.icon)
```

---

## API Response Examples

### Products API
```ruby
# api/products_controller.rb
render json: @products.as_json(
  include: {
    images: { methods: [:attachment_url] }
  }
)
```

Response:
```json
{
  "products": [
    {
      "id": 1,
      "name": "Product Name",
      "images": [
        {
          "id": 5,
          "attachment_url": "https://d3687nk8qb4e0v.cloudfront.net/abc123.webp"
        }
      ]
    }
  ]
}
```

### Categories API
```ruby
# api/categories_controller.rb
render json: @category.as_json.merge(
  attachment_url: @category.attachment_url
)
```

Response:
```json
{
  "id": 2,
  "name": "Fashion",
  "permalink": "categories/fashion",
  "attachment_url": "https://d3687nk8qb4e0v.cloudfront.net/696msb7j0sp6zytfuym7esfwso3y.webp"
}
```

---

## Troubleshooting

### "NoMethodError: undefined method `attachment_url`"

**Problem:** Calling on wrong object
```ruby
# ❌ Wrong - icon returns Attachment wrapper
taxon.icon.attachment_url

# ✅ Correct - call on model itself
taxon.attachment_url
```

### "Missing host to link to!"

**Problem:** Using `url_for` without controller context

**Solution:** Use `attachment_url` instead
```ruby
# ❌ Won't work in console/jobs
url_for(taxon.icon)

# ✅ Works everywhere
taxon.attachment_url
```

### Getting S3 URLs instead of CloudFront

**Problem:** Production override not loaded

**Check:**
```ruby
# In Rails console (production)
Spree::Taxon.find(2).attachment_url
# Should return CloudFront URL

# Check if override is loaded
Spree::ActiveStorageAdapter.instance_method(:attachment_url).source_location
# Should point to initializer if overridden
```

**Fix:** Ensure `config/initializers/active_storage_cloudfront.rb` is loaded

### CloudFront URLs not working

**Check environment variables:**
```bash
echo $CLOUDFRONT_URL
# Should output: https://d3687nk8qb4e0v.cloudfront.net
```

**Check Rails env:**
```ruby
Rails.env.production?  # Should be true
Rails.application.config.active_storage.service  # Should be :amazon
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `app/models/concerns/spree/active_storage_adapter.rb` | Base `attachment_url` implementation |
| `config/initializers/active_storage_cloudfront.rb` | Production CloudFront override |
| `app/controllers/api/products_controller.rb` | Example usage in API responses |
| `app/controllers/api/categories_controller.rb` | Example usage in API responses |
| `app/controllers/api/search_controller.rb` | Example usage in API responses |

---

## Best Practices

1. **Always use `attachment_url` in APIs**
   ```ruby
   # ✅ Good
   render json: @taxon.as_json.merge(attachment_url: @taxon.attachment_url)
   
   # ❌ Bad
   render json: @taxon.as_json.merge(icon_url: url_for(@taxon.icon))
   ```

2. **Check attachment before rendering**
   ```ruby
   # attachment_url already handles nil, but for clarity:
   if @taxon.icon.attached?
     render json: { icon_url: @taxon.attachment_url }
   end
   ```

3. **Use `methods:` option for collections**
   ```ruby
   # For including attachment_url in JSON
   @taxons.as_json(methods: [:attachment_url])
   ```

4. **Keep CloudFront URL in environment variables**
   ```bash
   # .env or production config
   CLOUDFRONT_URL=https://d3687nk8qb4e0v.cloudfront.net
   ```

---

## Summary

### Quick Decision Tree

**Need an attachment URL?**
- In API response? → Use `attachment_url` ✅
- In background job? → Use `attachment_url` ✅
- In model method? → Use `attachment_url` ✅
- In console testing? → Use `attachment_url` ✅
- In view with controller? → Can use `url_for` or `attachment_url` (prefer `attachment_url`)

**Why `attachment_url` is best:**
- ✅ Works in all contexts (no controller needed)
- ✅ Environment-aware (automatic CloudFront in production)
- ✅ Consistent across codebase
- ✅ Handles nil attachments
- ✅ Proper domain/host configuration
- ✅ Production-optimized (CDN URLs)

---

## Related Documentation

- [Rails Active Storage Guide](https://guides.rubyonrails.org/active_storage_overview.html)
- [Solidus Active Storage](https://github.com/solidusio/solidus/blob/master/core/app/models/concerns/spree/active_storage_adapter.rb)
- [CloudFront Documentation](https://aws.amazon.com/cloudfront/)

---

**Last Updated:** December 2, 2025





