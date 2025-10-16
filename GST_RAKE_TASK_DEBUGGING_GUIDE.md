# GST Rake Task Debugging Journey

## Overview

Running the `rake gst:setup` task encountered 7 different errors before final success. This document explains each issue and the fix applied.

---

## Issue #1: Column `spree_tax_rates.tax_category` Does Not Exist

### Error Message
```
ActiveRecord::StatementInvalid: PG::UndefinedColumn: ERROR:  
column spree_tax_rates.tax_category does not exist
```

### Root Cause
I assumed `spree_tax_rates` table had a `tax_category` column to directly store the tax category. This was incorrect - Solidus uses a **join table** `spree_tax_rate_tax_categories` for the many-to-many relationship.

### Original Code (WRONG)
```ruby
def create_tax_rate(name, tax_category, zone, rate, tax_type)
  Spree::TaxRate.find_or_create_by!(
    name: name,
    zone: zone,
    tax_category: tax_category,  # ❌ Column doesn't exist!
    amount: rate / 100.0,
    calculator_type: 'Spree::Calculator::DefaultTax',
    included_in_price: false
  )
end
```

### Fix Applied
```ruby
def create_tax_rate(name, tax_category, zone, rate, tax_type)
  tax_rate = Spree::TaxRate.find_or_create_by!(
    name: name,
    zone: zone,
    amount: rate / 100.0,
    included_in_price: false
  )
  
  # Associate tax category through join table
  tax_rate.tax_categories << tax_category unless tax_rate.tax_categories.include?(tax_category)
  
  tax_rate
end
```

### Key Learning
**Always check the actual database schema!** I ran this to discover the relationship:
```ruby
Spree::TaxRate.reflect_on_all_associations.map { |a| "#{a.name}: #{a.macro}" }
# => ["calculator: has_one", "zone: belongs_to", "tax_rate_tax_categories: has_many", "tax_categories: has_many"]
```

---

## Issue #2: Column `spree_tax_rates.calculator_type` Does Not Exist

### Error Message
```
ActiveRecord::StatementInvalid: PG::UndefinedColumn: ERROR:  
column spree_tax_rates.calculator_type does not exist
```

### Root Cause
I assumed `calculator_type` was a column on `spree_tax_rates`. Like the tax category, the calculator is a **separate model** (`Spree::Calculator`) with its own table.

### Original Code (WRONG)
```ruby
Spree::TaxRate.find_or_create_by!(
  name: name,
  zone: zone,
  amount: rate / 100.0,
  calculator_type: 'Spree::Calculator::DefaultTax',  # ❌ Not a column!
  included_in_price: false
)
```

### Discovery Process
I checked what columns actually exist:
```ruby
Spree::TaxRate.columns.map { |c| "#{c.name}: #{c.type}" }
# => id, amount, zone_id, included_in_price, created_at, updated_at, name, show_rate_in_label, deleted_at, starts_at, expires_at, level
```

The `calculator_type` wasn't there! But checking associations revealed:
```ruby
Spree::TaxRate.reflect_on_all_associations
# => ["calculator: has_one"]
```

### Fix Applied
Created and associated the `DefaultTax` calculator separately:

```ruby
def create_tax_rate(name, tax_category, zone, rate, tax_type)
  tax_rate = Spree::TaxRate.find_or_create_by!(
    name: name,
    zone: zone,
    amount: rate / 100.0,
    included_in_price: false
  ) do |tr|
    # Build calculator when creating tax rate
    tr.build_calculator(type: 'Spree::Calculator::DefaultTax')
  end
  
  # Create calculator if it doesn't exist
  tax_rate.build_calculator(type: 'Spree::Calculator::DefaultTax') unless tax_rate.calculator
  tax_rate.calculator&.save!
  
  tax_rate.tax_categories << tax_category unless tax_rate.tax_categories.include?(tax_category)
  tax_rate
end
```

### Key Learning
**Associations in Solidus are NOT simple column references!** They use:
- Join tables (many-to-many)
- Separate models (has_one, has_many)
- Polymorphic relationships

Always check the **actual schema** and **model associations**.

---

## Issue #3: Validation Failed - Shipping Category Can't Be Blank

### Error Message
```
ActiveRecord::RecordInvalid: Validation failed: Shipping category can't be blank
```

### Root Cause
Products in Solidus **require a shipping category**. I wasn't setting it during product creation.

### Original Code (WRONG)
```ruby
def create_product(name, price, description, tax_category)
  product = Spree::Product.find_or_create_by!(
    name: name,
    slug: name.downcase.gsub(/\s+/, '-'),
    description: description
  ) do |prod|
    prod.price = price
    prod.sku = name.upcase.gsub(/\s+/, '-')
    # ❌ Missing: prod.shipping_category = ...
  end
end
```

### Fix Applied
1. Created shipping category helper method:
```ruby
def create_shipping_category
  Spree::ShippingCategory.find_or_create_by!(name: 'Default')
end
```

2. Updated product creation to include it:
```ruby
def create_product(name, price, description, tax_category)
  shipping_category = Spree::ShippingCategory.find_by(name: 'Default') || create_shipping_category
  
  product = Spree::Product.find_or_create_by!(name: name) do |prod|
    prod.slug = name.downcase.gsub(/\s+/, '-')
    prod.description = description
    prod.price = price
    prod.shipping_category = shipping_category  # ✅ Now set!
  end
end
```

### Key Learning
**Solidus models have business-logic validations.** Products require:
- ✅ Shipping category (for logistics)
- ✅ Tax category (for taxation)
- ✅ At least one variant (with SKU and price)

Always check `Model.validators` or model validations when you hit validation errors.

---

## Issue #4: SKU Has Already Been Taken

### Error Message
```
ActiveRecord::RecordInvalid: Validation failed: SKU has already been taken
```

### Root Cause
The rake task was creating products with the same SKU on each run, but I was using `find_or_create_by` on the product level while creating brand new variants with the same SKU. This caused conflicts on re-runs.

### Problem Flow
```
First run:
  1. Product "Samsung Galaxy S24" created
  2. Variant with SKU "SAMSUNG-GALAXY-S24" created
  ✅ Success

Second run:
  1. Product "Samsung Galaxy S24" found (exists)
  2. Variant with SKU "SAMSUNG-GALAXY-S24" created  ❌ Already exists!
```

### Original Code (WRONG)
```ruby
product = Spree::Product.find_or_create_by!(name: name) do |prod|
  # ... set fields ...
end

# This tried to create a NEW variant with same SKU
if product.variants.empty?
  variant = product.variants.build(
    sku: sku,
    price: price
  )
  variant.save!  # ❌ SKU conflict!
end
```

### Fix Applied
Changed to use `find_or_create_by` on **variant level** with SKU:

```ruby
product = Spree::Product.find_or_create_by!(name: name) do |prod|
  prod.slug = name.downcase.gsub(/\s+/, '-')
  prod.description = description
  prod.price = price
  prod.shipping_category = shipping_category
end

# Find or create variant by SKU (truly idempotent!)
variant = Spree::Variant.find_or_create_by!(sku: sku) do |var|
  var.product = product
  var.price = price
end
```

### Key Learning
**For idempotent rake tasks, use find_or_create_by at the DETAIL level, not the parent level.**

Bad approach:
```
Product.find_or_create_by(name) → then try to create variant
```

Good approach:
```
Variant.find_or_create_by(sku) → associates with product automatically
```

---

## Issue #5: Multiple SKU Conflicts with Different Variants

### Error Message
Same as Issue #4, but appearing in different scenarios

### Root Cause
Intermediate attempt used `first_or_create!` which still had timing issues:

```ruby
variant = product.variants.first_or_create!(
  sku: sku,
  price: price
)
```

This would:
1. Check if product has variants → yes from previous run
2. Use first variant → but it might have a different SKU
3. Try to update SKU on existing variant → conflict!

### Fix Applied
Moved from product-scoped variant creation to global `Spree::Variant.find_or_create_by!`:

```ruby
# ✅ CORRECT: Look up variant globally by SKU
variant = Spree::Variant.find_or_create_by!(sku: sku) do |var|
  var.product = product
  var.price = price
end
```

This ensures:
- Same product name on re-run → finds existing product ✅
- Same SKU on re-run → finds existing variant ✅
- New product → creates new product ✅
- New SKU → creates new variant ✅

---

## Summary of All Issues and Fixes

| # | Issue | Root Cause | Fix | Key Learning |
|---|-------|-----------|-----|--------------|
| 1 | `tax_category` column missing | Assumed direct column | Use join table `tax_rate_tax_categories` | Always check actual schema |
| 2 | `calculator_type` column missing | Assumed direct column | Create separate `Spree::Calculator` model | Solidus uses relationships, not direct columns |
| 3 | Shipping category validation | Didn't set required field | Set `shipping_category` during creation | Check model validations |
| 4 | SKU uniqueness conflict | Find/create at wrong level | Use `Variant.find_or_create_by!(sku:)` | Be specific with find_or_create scope |
| 5 | Multiple SKU conflicts | Used product-scoped variant creation | Move to global variant lookup | Global keys are more reliable |
| 6 | (N/A) | (N/A) | (N/A) | (N/A) |
| 7 | ✅ SUCCESS | All fixed | Rake task runs successfully | Idempotent and repeatable |

---

## Debugging Techniques Used

### 1. Rails Console Inspection
```ruby
# Check table structure
Spree::TaxRate.columns.map { |c| "#{c.name}: #{c.type}" }

# Check associations
Spree::TaxRate.reflect_on_all_associations
  .map { |a| "#{a.name}: #{a.macro}" }

# Test manually
calculator = Spree::Calculator::DefaultTax.create!(calculable: tax_rate)
```

### 2. Error Stack Traces
Each error provided valuable info:
- Line number where error occurred
- SQL query that failed
- Column/attribute that caused problem

### 3. Database Schema Reading
```ruby
# In Rails console
Spree::TaxRate.columns
Spree::Variant.columns
Spree::Product.columns
```

### 4. Model Validator Checking
```ruby
Spree::Product.validators
# Shows what's required and optional
```

---

## Final Working Solution

```ruby
# ✅ All issues fixed:
# 1. Tax rates created without direct columns
# 2. Calculator associated via has_one relationship
# 3. Shipping category set during creation
# 4. Products found/created by name (idempotent)
# 5. Variants found/created by SKU (idempotent)
# 6. Tax categories associated via join table

rake gst:setup  # ✅ SUCCESS on any run!
```

---

## Lessons Learned

### 1. **Always Inspect the Schema**
Don't assume column names. Check:
- `Model.columns`
- `Model.reflect_on_all_associations`
- Database migrations

### 2. **Solidus Uses Complex Relationships**
- Many-to-many: Join tables
- Polymorphic: Can belong to multiple model types
- Separate models: For calculators, adjustments, etc.

### 3. **Make Rake Tasks Idempotent**
- Use `find_or_create_by` at the most specific level
- Choose natural keys (SKU, not ID)
- Test by running multiple times

### 4. **Read Error Messages Carefully**
- Column names tell you about schema structure
- Line numbers point to exact problems
- SQL queries show what Rails is actually trying

### 5. **Validate Incrementally**
- Test each method independently
- Create a simple test before full task
- Build from simple to complex

---

## How to Debug Similar Issues

When you encounter a Solidus error:

1. **Check the schema:**
   ```ruby
   Model.columns
   Model.reflect_on_all_associations
   ```

2. **Check the validators:**
   ```ruby
   Model.validators
   ```

3. **Try in console:**
   ```ruby
   rails console
   # Try creating the object step by step
   ```

4. **Read the error:**
   - Line number
   - Missing column/attribute
   - SQL query

5. **Search Solidus docs:**
   - Model relationships
   - Required validations
   - Usage patterns
