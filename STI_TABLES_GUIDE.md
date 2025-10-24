# Single Table Inheritance (STI) Tables in Solidus

## What is Single Table Inheritance (STI)?

Single Table Inheritance (STI) is a Rails pattern where multiple models (classes) share a single database table. The table includes a `type` column that stores the class name, allowing Rails to instantiate the correct model class when retrieving records.

**Benefits:**
- Reduces number of database tables
- Simplifies queries across related types
- Shared attributes and behavior across subclasses

**Key Indicators:**
- A `type` column (string type) in the database table
- Multiple model classes inheriting from a base model
- All models using the same table

---

## How to Find STI Tables

### Step 1: Search the Schema for Type Columns

The primary indicator of STI is a `type` column in the database schema.

```bash
# Search for lines containing 't.string "type"' in the schema
grep -n 't.string "type"' db/schema.rb
```

**Alternative using grep tool:**
```bash
# Search for type columns with context
grep 'type.*string' db/schema.rb
```

### Step 2: Read the Schema File

Read the entire schema to understand table structures:

```bash
# View the complete schema
cat db/schema.rb

# Or search for specific table definitions
grep -A 20 'create_table "spree_' db/schema.rb | grep -B 5 'type'
```

### Step 3: Identify Base Models

Look for base model classes that other models inherit from:

```bash
# Search for common STI base classes in models
find app/models -name "*.rb" -exec grep -l "class.*< Spree::" {} \;

# Search for specific base classes
grep -r "< Spree::Calculator" app/models/
grep -r "< Spree::PaymentMethod" app/models/
grep -r "< Spree::Asset" app/models/
```

### Step 4: List Model Directories

Check for organized subdirectories that suggest STI hierarchies:

```bash
# List model subdirectories
ls -la app/models/spree/calculator/
ls -la app/models/spree/payment_method/
ls -la app/models/spree/reimbursement_type/

# Find all files in STI-related directories
find app/models/spree/calculator -name "*.rb"
find app/models/spree/payment_method -name "*.rb"
```

### Step 5: Read Base Model Files

Examine base model files for STI documentation:

```bash
# Read the base models
cat app/models/spree/calculator.rb
cat app/models/spree/payment_method.rb
cat app/models/spree/reimbursement_type.rb
cat app/models/spree/asset.rb
```

### Step 6: Verify Subclass Implementations

Look at concrete implementations to confirm inheritance:

```bash
# Check specific subclasses
cat app/models/spree/calculator/flat_rate.rb
cat app/models/spree/payment_method/store_credit.rb
cat app/models/spree/reimbursement_type/store_credit.rb
cat app/models/spree/image.rb
```

---

## STI Tables Found in This Application

### 1. `spree_assets`
**Location in schema:** Line 145-163

**Type column:**
```ruby
t.string "type", limit: 75
```

**Base model:** `Spree::Asset`

**Subclasses:**
- `Spree::Image` - Handles product images

**Verification command:**
```bash
grep -r "< Asset" app/models/spree/
cat app/models/spree/image.rb
```

---

### 2. `spree_calculators`
**Location in schema:** Line 165-174

**Type column:**
```ruby
t.string "type"
```

**Indexes:**
```ruby
t.index ["id", "type"], name: "index_spree_calculators_on_id_and_type"
```

**Base model:** `Spree::Calculator`

**Subclasses:**
- `Spree::Calculator::FlatRate`
- `Spree::Calculator::FlatFee`
- `Spree::Calculator::DefaultTax`
- `Spree::ShippingCalculator`
  - `Spree::Calculator::Shipping::FlatRate`
  - `Spree::Calculator::Shipping::PerItem`
  - `Spree::Calculator::Shipping::PriceSack`
  - `Spree::Calculator::Shipping::FlexiRate`
  - `Spree::Calculator::Shipping::FlatPercentItemTotal`
- `Spree::ReturnsCalculator`
  - `Spree::Calculator::Returns::DefaultRefundAmount`

**Verification commands:**
```bash
cat app/models/spree/calculator.rb
find app/models/spree/calculator -name "*.rb"
cat app/models/spree/calculator/flat_rate.rb
```

---

### 3. `spree_payment_methods`
**Location in schema:** Line 393-409

**Type column:**
```ruby
t.string "type"
```

**Indexes:**
```ruby
t.index ["id", "type"], name: "index_spree_payment_methods_on_id_and_type"
```

**Base model:** `Spree::PaymentMethod` (explicitly documented as using STI in the model)

**Documentation from source:**
> Uses STI (single table inheritance) to store all implemented payment methods in one table (+spree_payment_methods+).

**Subclasses:**
- `Spree::PaymentMethod::StoreCredit`
- `Spree::PaymentMethod::CreditCard`
- `Spree::PaymentMethod::Check`
- `Spree::PaymentMethod::BogusCreditCard`
- `Spree::PaymentMethod::SimpleBogusCreditCard`

**Verification commands:**
```bash
cat app/models/spree/payment_method.rb
find app/models/spree/payment_method -name "*.rb"
cat app/models/spree/payment_method/store_credit.rb
```

---

### 4. `spree_promotion_actions`
**Location in schema:** Line 530-541

**Type column:**
```ruby
t.string "type"
```

**Indexes:**
```ruby
t.index ["id", "type"], name: "index_spree_promotion_actions_on_id_and_type"
```

**Base model:** `Spree::PromotionAction` (from solidus_legacy_promotions gem)

**Verification command:**
```bash
grep -r "PromotionAction" app/models/
```

---

### 5. `spree_promotion_rules`
**Location in schema:** Line 583-590

**Type column:**
```ruby
t.string "type"
```

**Base model:** `Spree::PromotionRule` (from solidus_legacy_promotions gem)

**Verification command:**
```bash
grep -r "PromotionRule" app/models/
```

---

### 6. `spree_promotions`
**Location in schema:** Line 610-630

**Type column:**
```ruby
t.string "type"
```

**Indexes:**
```ruby
t.index ["id", "type"], name: "index_spree_promotions_on_id_and_type"
```

**Base model:** `Spree::Promotion` (from solidus_legacy_promotions gem)

**Verification command:**
```bash
grep -r "< Spree::Promotion" app/models/
```

---

### 7. `spree_reimbursement_types`
**Location in schema:** Line 694-702

**Type column:**
```ruby
t.string "type"
```

**Indexes:**
```ruby
t.index ["type"], name: "index_spree_reimbursement_types_on_type"
```

**Base model:** `Spree::ReimbursementType`

**Subclasses:**
- `Spree::ReimbursementType::StoreCredit`
- `Spree::ReimbursementType::OriginalPayment`
- `Spree::ReimbursementType::Exchange`
- `Spree::ReimbursementType::Credit`

**Verification commands:**
```bash
cat app/models/spree/reimbursement_type.rb
find app/models/spree/reimbursement_type -name "*.rb"
cat app/models/spree/reimbursement_type/store_credit.rb
```

---

## Complete Command Sequence

Here's a complete command sequence to identify all STI tables:

```bash
# 1. Find all tables with 'type' columns
echo "=== Tables with 'type' column ==="
grep -n '"type"' db/schema.rb | grep 't.string'

# 2. List model directories that suggest STI
echo -e "\n=== Model subdirectories (STI candidates) ==="
ls -d app/models/spree/*/ 2>/dev/null | head -20

# 3. Search for common base classes
echo -e "\n=== Calculator subclasses ==="
find app/models -name "*.rb" -exec grep -l "< .*Calculator" {} \;

echo -e "\n=== PaymentMethod subclasses ==="
find app/models -name "*.rb" -exec grep -l "< .*PaymentMethod" {} \;

echo -e "\n=== ReimbursementType subclasses ==="
find app/models -name "*.rb" -exec grep -l "< .*ReimbursementType" {} \;

echo -e "\n=== Asset subclasses ==="
find app/models -name "*.rb" -exec grep -l "< .*Asset" {} \;

# 4. Check for STI documentation in models
echo -e "\n=== Models mentioning STI ==="
grep -r "STI\|single table inheritance" app/models/ --include="*.rb"

# 5. List all calculator implementations
echo -e "\n=== All Calculator implementations ==="
find app/models/spree/calculator -name "*.rb" 2>/dev/null

# 6. List all payment method implementations
echo -e "\n=== All PaymentMethod implementations ==="
find app/models/spree/payment_method -name "*.rb" 2>/dev/null

# 7. List all reimbursement type implementations
echo -e "\n=== All ReimbursementType implementations ==="
find app/models/spree/reimbursement_type -name "*.rb" 2>/dev/null
```

---

## Using Rails Console

You can also verify STI tables using the Rails console:

```ruby
# Start Rails console
rails console

# Check if a model uses STI
Spree::Calculator.inheritance_column
# => "type"

# List all subclasses
Spree::Calculator.descendants.map(&:name)
Spree::PaymentMethod.descendants.map(&:name)
Spree::ReimbursementType.descendants.map(&:name)

# Query by type
Spree::Calculator.where(type: 'Spree::Calculator::FlatRate')
Spree::PaymentMethod.where(type: 'Spree::PaymentMethod::StoreCredit')

# Check table name (all subclasses use same table)
Spree::Calculator::FlatRate.table_name
# => "spree_calculators"
Spree::Calculator::DefaultTax.table_name
# => "spree_calculators"
```

---

## Database Queries

Verify STI directly in the database:

```sql
-- Check distinct types in spree_calculators
SELECT DISTINCT type FROM spree_calculators;

-- Check distinct types in spree_payment_methods
SELECT DISTINCT type FROM spree_payment_methods;

-- Check distinct types in spree_reimbursement_types
SELECT DISTINCT type FROM spree_reimbursement_types;

-- Check distinct types in spree_assets
SELECT DISTINCT type FROM spree_assets;

-- Check distinct types in spree_promotion_actions
SELECT DISTINCT type FROM spree_promotion_actions;

-- Check distinct types in spree_promotion_rules
SELECT DISTINCT type FROM spree_promotion_rules;

-- Check distinct types in spree_promotions
SELECT DISTINCT type FROM spree_promotions;

-- Count records by type
SELECT type, COUNT(*) 
FROM spree_calculators 
GROUP BY type;
```

---

## Summary Table

| Table Name | Type Column | Base Model | # of Known Subclasses | Schema Line |
|------------|-------------|------------|-----------------------|-------------|
| `spree_assets` | `type` (limit: 75) | `Spree::Asset` | 1+ | 145-163 |
| `spree_calculators` | `type` | `Spree::Calculator` | 11+ | 165-174 |
| `spree_payment_methods` | `type` | `Spree::PaymentMethod` | 5+ | 393-409 |
| `spree_promotion_actions` | `type` | `Spree::PromotionAction` | Multiple (from gem) | 530-541 |
| `spree_promotion_rules` | `type` | `Spree::PromotionRule` | Multiple (from gem) | 583-590 |
| `spree_promotions` | `type` | `Spree::Promotion` | Multiple (from gem) | 610-630 |
| `spree_reimbursement_types` | `type` | `Spree::ReimbursementType` | 4+ | 694-702 |

**Total: 7 STI Tables**

---

## Tips for Working with STI

1. **Always specify the type when creating records:**
   ```ruby
   Spree::Calculator::FlatRate.create(...)
   # NOT: Spree::Calculator.create(type: '...')
   ```

2. **Use subclass scopes:**
   ```ruby
   Spree::Calculator::FlatRate.all
   # Better than: Spree::Calculator.where(type: 'Spree::Calculator::FlatRate')
   ```

3. **Be aware of eager loading:**
   ```ruby
   # This loads all types
   Spree::Calculator.all
   
   # This only loads FlatRate types
   Spree::Calculator::FlatRate.all
   ```

4. **Check indexes on type columns for performance:**
   Most STI tables have composite indexes on `[id, type]` for optimal query performance.

---

## Related Documentation

- [Rails STI Guide](https://api.rubyonrails.org/classes/ActiveRecord/Inheritance.html)
- [Solidus Guides](https://guides.solidus.io/)
- `RAILS_ASSOCIATIONS_GUIDE.md` - For relationship patterns
- `db/schema.rb` - Current database schema

---

**Last Updated:** October 21, 2025
**Application:** Solidus E-commerce Platform
**Rails Version:** 7.1

