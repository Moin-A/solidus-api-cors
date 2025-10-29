# Shipping Configuration Guide - From Checkout to Shipping Rates

This guide documents the complete flow from checkout API call to shipping rate calculation, debugging why shipping rates were empty, and the solution implementation.

---

## Table of Contents
1. [The Complete Chain: Update Action to Shipping Methods](#the-complete-chain)
2. [Why available_for_address Returns Empty Array](#why-available_for_address-returns-empty)
3. [Creating India-Specific Shipping Configuration](#creating-india-shipping-configuration)
4. [Script Iterations and Error Fixes](#script-iterations-and-errors)

---

## The Complete Chain

### Starting Point: API Call

```bash
PUT /api/checkouts/R708360513/next
```

### Flow Through the System

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: CheckoutsController#next (Line 15)                  │
├─────────────────────────────────────────────────────────────┤
│ File: app/controllers/spree/api/checkouts_controller.rb    │
│                                                              │
│ def next                                                     │
│   @order.next!  # ← Calls state machine event               │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 2: State Machine Transition                            │
├─────────────────────────────────────────────────────────────┤
│ File: app/models/spree/core/state_machines/order/          │
│       class_methods.rb (Line 38-39)                         │
│                                                              │
│ state_machine :state do                                     │
│   transition(from: :address, to: :delivery, on: :next)     │
│ end                                                          │
│                                                              │
│ Triggers before_transition callbacks...                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 3: before_transition Callbacks (Lines 99-103)          │
├─────────────────────────────────────────────────────────────┤
│ if states[:delivery]                                        │
│   before_transition to: :delivery, do:                      │
│                       :ensure_shipping_address              │
│   before_transition to: :delivery, do:                      │
│                       :create_proposed_shipments ← KEY!     │
│   before_transition to: :delivery, do:                      │
│                       :ensure_available_shipping_rates      │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Order#create_proposed_shipments                     │
├─────────────────────────────────────────────────────────────┤
│ File: app/models/spree/order_shipping.rb (approx)          │
│                                                              │
│ def create_proposed_shipments                               │
│   shipments.destroy_all  # Clear old shipments              │
│   coordinator = Spree::Config.stock.coordinator_class.new   │
│   coordinator.shipments = coordinator.build_shipments(self) │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 5: SimpleCoordinator#build_shipments                   │
├─────────────────────────────────────────────────────────────┤
│ File: app/models/spree/stock/simple_coordinator.rb         │
│                                                              │
│ def build_shipments(order)                                  │
│   packages = build_packages(order)                          │
│   build_shipments_from_packages(packages)                   │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 6: SimpleCoordinator#build_shipments_from_packages     │
├─────────────────────────────────────────────────────────────┤
│ def build_shipments                                         │
│   packages.map do |package|                                 │
│     shipment = package.to_shipment                          │
│     shipment.shipping_rates = estimator.shipping_rates(pkg) │
│   end                                                        │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 7: Estimator#shipping_rates (Line 16)                 │
├─────────────────────────────────────────────────────────────┤
│ File: app/models/spree/stock/estimator.rb                  │
│                                                              │
│ def shipping_rates(package, frontend_only = true)          │
│   rates = calculate_shipping_rates(package) ← KEY!          │
│   rates.select! { ... } if frontend_only                    │
│   choose_default_shipping_rate(rates)                       │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 8: Estimator#calculate_shipping_rates (Line 35-54)    │
├─────────────────────────────────────────────────────────────┤
│ def calculate_shipping_rates(package)                       │
│   shipping_methods(package).map do |shipping_method|        │
│     cost = shipping_method.calculator.compute(package)      │
│     if cost                                                  │
│       rate = shipping_method.shipping_rates.new(cost: cost) │
│     end                                                      │
│   end.compact                                                │
│ end                                                          │
│                                                              │
│ Returns: Array of ShippingRate objects                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 9: Estimator#shipping_methods (Line 56-68) ← PROBLEM! │
├─────────────────────────────────────────────────────────────┤
│ def shipping_methods(package)                               │
│   package.shipping_methods                                  │
│     .available_to_store(package.shipment.order.store)       │
│     .available_for_address(ship_address) ← RETURNS []       │
│     .includes(:calculator)                                   │
│     .to_a                                                    │
│     .select { |m| calculator.available?(package) }          │
│ end                                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Why `available_for_address` Returns Empty

### The Method Chain

```ruby
# From Estimator#shipping_methods (line 56-68)
package.shipping_methods
  .available_to_store(order.store)              # Filter 1
  .available_for_address(order.ship_address)    # Filter 2 ← FAILS HERE!
  .includes(:calculator)
  .to_a
  .select { |m| m.calculator.available?(package) }  # Filter 3
```

### Filter Breakdown

#### Filter 1: `available_to_store`

**What it checks:** Is shipping method associated with this store?

```ruby
# From ShippingMethod model
scope :available_to_store, ->(store) do
  store.shipping_methods.empty? ? all : where(id: store.shipping_methods.ids)
end
```

**Passes if:**
- Shipping method is in `store.shipping_methods` association
- Or no shipping methods configured for store (returns all)

#### Filter 2: `available_for_address` ← THE PROBLEM

**What it checks:** Does shipping method's zones include this address's country?

```ruby
# Simplified logic
def available_for_address(address)
  where(id: Zone.for_address(address).joins(:shipping_methods).select(:shipping_method_id))
end

# Zone.for_address checks:
# - Does any zone's members include this address's country or state?
```

**Your Case:**
```ruby
# Order address
ship_address.country_id = 105  # India

# Shipping method
method.name = "UPS Ground (USD)"
method.zones.first.name = "North America"  # ← Only includes US, Canada, Mexico

# Check
method.zones.first.countries.pluck(:id)  # => [232, 40, 142] (US, Canada, Mexico)
# Does NOT include 105 (India)!

# Result
available_for_address(india_address)  # => [] ❌
```

#### Filter 3: Calculator Available

**What it checks:** Can calculator compute a cost for this package?

```ruby
calculator.available?(package) &&
  (calculator.preferences[:currency].blank? ||
   calculator.preferences[:currency] == package.order.currency)
```

**Would also fail:**
- Calculator currency: USD
- Order currency: INR
- Doesn't match → Filtered out

### Visual Flow of Filters

```
All Shipping Methods
  ↓ available_to_store
Shipping Methods for Store X
  ↓ available_for_address (INDIA)
[] ← EMPTY! None have zone including India
  ↓
[] ← Can't proceed to calculator check
```

### The Root Cause

**Shipping method zones don't include India:**

```
Shipping Method: "UPS Ground (USD)"
  ↓ has zones
Zone: "North America"
  ↓ has countries
[USA, Canada, Mexico]  ← India NOT here! ❌
```

---

## Creating India-Specific Shipping Configuration

### Requirements Analysis

To make shipping rates appear, we need:

1. ✅ **Zone** containing India
2. ✅ **Shipping Method** associated with that zone
3. ✅ **Shipping Category** (what products can be shipped)
4. ✅ **Calculator** (how to calculate shipping cost)
5. ✅ **Store Association** (which stores can use this method)
6. ✅ **Currency Match** (calculator currency = order currency)

### The Solution Script

**Created:** `db/seeds/setup_india_shipping.rb`

**What It Does:**

```ruby
# 1. Find/Create India country
india = Spree::Country.find_by(iso: "IN")

# 2. Create zone for India
india_zone = Spree::Zone.create!(name: "India Shipping Zone")

# 3. Add India to zone
india_zone.zone_members.create!(zoneable: india)

# 4. Create shipping category
category = Spree::ShippingCategory.find_or_create_by!(name: "Default")

# 5. Create shipping method with everything needed at once
india_method = Spree::ShippingMethod.new(
  name: "India Standard Shipping",
  shipping_categories: [category],  # ← Required
  zones: [india_zone],               # ← Required
  stores: [Spree::Store.default]     # ← Required
)

# 6. Create calculator (required by validation)
india_method.calculator = Spree::Calculator::Shipping::FlatRate.new(
  preferences: { amount: 50.00, currency: "INR" }
)

india_method.save!

# 7. Assign category to products
Spree::Variant.update_all(shipping_category_id: category.id)
```

---

## Script Iterations and Errors

### Iteration 1: Initial Attempt

**Code:**
```ruby
india_method = Spree::ShippingMethod.create!(
  name: "India Standard Shipping",
  display_on: "both"
)
```

**Error:**
```
ActiveModel::UnknownAttributeError: unknown attribute 'display_on' for Spree::ShippingMethod
```

**Cause:** `display_on` doesn't exist in the ShippingMethod model schema.

**Fix:** Removed `display_on` attribute.

---

### Iteration 2: Validation Errors

**Code:**
```ruby
india_method = Spree::ShippingMethod.new(name: "...")
india_method.save!
# Then associate zones/categories
india_method.zones << zone
```

**Error:**
```
Validation failed: Calculator can't be blank, 
You need to select at least one shipping category
```

**Cause:** ShippingMethod has validations:
- `validates :calculator, presence: true` (from `CalculatedAdjustments` concern)
- `validate :at_least_one_shipping_category` (from ShippingMethod model)

**Problem:** We were trying to save BEFORE adding required associations.

**Fix:** Add associations BEFORE saving:

```ruby
india_method = Spree::ShippingMethod.new(name: "...")

# Add these BEFORE save!
india_method.shipping_categories << category
india_method.calculator = Calculator.new(...)

india_method.save!  # ✅ Now passes validation
```

---

### Iteration 3: Variable Scope Issue

**Code:**
```ruby
# Earlier in script
default_store = Spree::Store.default
india_method.stores << default_store

# Much later...
if default_store.default_currency != "INR"  # ← Error here
```

**Error:**
```
NameError: undefined local variable or method `default_store' for main:Object
```

**Cause:** Variable `default_store` was defined inside a conditional block and not accessible later.

**Fix:** Define `default_store` again before using it:

```ruby
# Later in script
default_store = Spree::Store.default  # ← Re-define
if default_store.default_currency != "INR"
  # ...
end
```

---

### Final Working Version

```ruby
# 1. Get references
india = Spree::Country.find(105)
category = Spree::ShippingCategory.find_or_create_by!(name: "Default")

# 2. Create zone
india_zone = Spree::Zone.find_or_create_by!(name: "India Shipping Zone")
india_zone.zone_members.find_or_create_by!(zoneable: india)

# 3. Create shipping method with all required associations
india_method = Spree::ShippingMethod.new(
  name: "India Standard Shipping",
  admin_name: "India Standard",
  available_to_users: true,
  available_to_all: true
)

# CRITICAL: Add these BEFORE save!
india_method.shipping_categories << category
india_method.zones << india_zone
india_method.stores << Spree::Store.default

# CRITICAL: Create calculator BEFORE save!
india_method.calculator = Spree::Calculator::Shipping::FlatRate.new(
  preferences: { amount: 50.00, currency: "INR" }
)

india_method.save!  # ✅ Now validates

# 4. Assign to variants
Spree::Variant.update_all(shipping_category_id: category.id)
```

---

## Detailed Method Analysis

### Method 1: `available_to_store`

**Location:** `app/models/spree/shipping_method.rb`

**Code:**
```ruby
scope :available_to_store, ->(store) do
  raise ArgumentError, "You must provide a store" if store.nil?
  store.shipping_methods.empty? ? all : where(id: store.shipping_methods.ids)
end
```

**What it does:**
- If store has NO shipping methods configured → Return ALL shipping methods
- If store HAS shipping methods → Return only those associated with the store

**SQL Generated:**
```sql
SELECT * FROM spree_shipping_methods
WHERE id IN (
  SELECT shipping_method_id 
  FROM spree_store_shipping_methods 
  WHERE store_id = ?
)
```

**Passes if:** `ShippingMethod.stores` includes the order's store

---

### Method 2: `available_for_address` (THE KEY METHOD)

**Location:** Likely in Solidus Core gem

**What it checks:**
```ruby
def available_for_address(address)
  # Find zones that include this address
  zones = Zone.for_address(address)
  
  # Find shipping methods in those zones
  where(id: zones.joins(:shipping_methods).select(:shipping_method_id))
end
```

**Step-by-Step:**

1. **Get address details:**
   ```ruby
   address.country_id = 105  # India
   address.state_id = 1164   # Maharashtra
   ```

2. **Find zones containing this address:**
   ```ruby
   Zone.for_address(address)
   # Checks zone_members for:
   # - zoneable_type = 'Spree::Country', zoneable_id = 105
   # - OR zoneable_type = 'Spree::State', zoneable_id = 1164
   ```

3. **Your case:**
   ```ruby
   # Existing zones
   Zone.all.map { |z| [z.name, z.countries.pluck(:name)] }
   # => [["North America", ["United States", "Canada", "Mexico"]]]
   
   # Zone.for_address(india_address)
   # => [] ← No zone contains India!
   ```

4. **Find shipping methods in those zones:**
   ```ruby
   zones = []  # No zones found
   zones.joins(:shipping_methods)  # => []
   # Result: No shipping methods available
   ```

**Why it returned `[]`:**

```
Check: Does any Zone include country_id: 105 (India)?
  ↓
Query zone_members:
  SELECT * FROM spree_zone_members 
  WHERE zoneable_type = 'Spree::Country' 
    AND zoneable_id = 105

Result: 0 records ← India not in any zone!
  ↓
No zones found for address
  ↓
No shipping methods in those zones
  ↓
available_for_address returns [] ❌
```

---

### Method 3: Calculator Check

**Code:**
```ruby
.select do |ship_method|
  calculator = ship_method.calculator
  calculator.available?(package) &&
    (calculator.preferences[:currency].blank? ||
     calculator.preferences[:currency] == package.order.currency)
end
```

**What it checks:**
- Calculator can process this package (usually always true for FlatRate)
- Calculator currency matches order currency OR calculator has no currency preference

**Your case (before fix):**
```ruby
calculator.preferences[:currency] = "USD"
order.currency = "INR"  # After changing store currency

# Check
"USD" == "INR"  # => false ❌
# Would be filtered out even if it passed zone check!
```

---

## Why Each Filter Matters

### Filter Chain Example

```
Start: 5 shipping methods in database

Filter 1 (available_to_store):
  Store has methods: [1, 2, 3]
  Result: 3 methods
  
Filter 2 (available_for_address):
  Address in India
  Only method 1 has zone including India
  Result: 1 method
  
Filter 3 (calculator check):
  Method 1 calculator: currency = "USD"
  Order currency: "INR"
  Doesn't match!
  Result: 0 methods ❌

Final: [] (No shipping rates calculated)
```

---

## The Complete Solution

### Database Setup Required

```
┌──────────────────────┐
│ Spree::Country       │
│ id: 105, iso: "IN"  │
│ name: "India"        │
└──────────────────────┘
          ↓ included in
┌──────────────────────┐
│ Spree::ZoneMember    │
│ zone_id: 5           │
│ zoneable_id: 105     │
│ zoneable_type:       │
│ "Spree::Country"     │
└──────────────────────┘
          ↓ belongs to
┌──────────────────────┐
│ Spree::Zone          │
│ id: 5                │
│ name: "India Zone"   │
└──────────────────────┘
          ↓ has
┌──────────────────────────────────┐
│ Spree::ShippingMethodZone        │
│ shipping_method_id: 11           │
│ zone_id: 5                       │
└──────────────────────────────────┘
          ↓ belongs to
┌──────────────────────────────────┐
│ Spree::ShippingMethod            │
│ id: 11                           │
│ name: "India Standard Shipping"  │
└──────────────────────────────────┘
          ↓ has
┌──────────────────────────────────┐
│ Spree::Calculator::FlatRate      │
│ calculable_id: 11                │
│ calculable_type:                 │
│ "Spree::ShippingMethod"          │
│ preferences:                     │
│   { amount: 50, currency: "INR" }│
└──────────────────────────────────┘
```

---

## Common Issues and Solutions

### Issue 1: No Shipping Methods Returned

**Symptom:** `shipping_methods(package)` returns `[]`

**Check:**
```ruby
# Are there any shipping methods?
Spree::ShippingMethod.count

# Are they available to the store?
Spree::ShippingMethod.available_to_store(order.store).count

# Do zones include the address?
method = Spree::ShippingMethod.first
method.zones.each do |zone|
  puts zone.countries.pluck(:name)
end
```

**Solutions:**
- Create shipping method if none exist
- Associate with store
- Create zone with address's country

---

### Issue 2: Calculator Returns Nil

**Symptom:** `calculator.compute(package)` returns `nil`

**Check:**
```ruby
method.calculator  # Exists?
method.calculator.class.name  # What type?
method.calculator.preferences  # Has amount?
```

**Solutions:**
```ruby
# Create calculator
Spree::Calculator::Shipping::FlatRate.create!(
  calculable: method,
  preferences: { amount: 50, currency: "INR" }
)
```

---

### Issue 3: Currency Mismatch

**Symptom:** Calculator currency doesn't match order currency

**Check:**
```ruby
calculator.preferences[:currency]  # => "USD"
order.currency  # => "INR"
```

**Solutions:**
```ruby
# Update calculator currency
calculator.update!(
  preferences: { 
    amount: 50,
    currency: "INR"  # Match order currency
  }
)

# Or leave currency blank (works with all currencies)
calculator.update!(
  preferences: { 
    amount: 50,
    currency: nil
  }
)
```

---

### Issue 4: Shipping Category Missing

**Symptom:** Products/Variants have no `shipping_category_id`

**Check:**
```ruby
Spree::Variant.where(shipping_category_id: nil).count
```

**Solution:**
```ruby
category = Spree::ShippingCategory.first
Spree::Variant.update_all(shipping_category_id: category.id)
```

---

## Debugging Checklist

When shipping rates are empty, check in order:

### 1. Does Shipping Method Exist?
```ruby
Spree::ShippingMethod.count  # > 0?
```

### 2. Is It Associated with Store?
```ruby
method = Spree::ShippingMethod.first
method.stores.include?(Spree::Store.default)  # true?
```

### 3. Does Zone Include Address Country?
```ruby
order.ship_address.country  # => India
method.zones.first.countries  # Includes India?
```

### 4. Does Method Have Shipping Category?
```ruby
method.shipping_categories.any?  # true?
```

### 5. Does Calculator Exist?
```ruby
method.calculator  # Not nil?
```

### 6. Does Currency Match?
```ruby
method.calculator.preferences[:currency]  # => "INR" or nil
order.currency  # => "INR"
```

### 7. Can Calculator Compute?
```ruby
package = order.shipments.first.to_package
method.calculator.compute(package)  # Returns number, not nil?
```

### 8. Do Products Have Shipping Category?
```ruby
order.line_items.first.variant.shipping_category_id  # Not nil?
```

---

## Script Execution Log

### Successful Run Output

```
🇮🇳 Setting up India shipping configuration...
✅ Found India (ID: 105, Name: India)
✅ Added India to zone (Zone members: 1)
✅ Shipping category: Default (ID: 1)
✅ Created India Standard Shipping method (ID: 11)
✅ Created flat rate calculator (₹50.00 INR)
✅ Assigned shipping category to 0 products
✅ Assigned shipping category to 97 variants

============================================================
🎉 India Shipping Setup Complete!
============================================================

📋 Verification:
- Shipping Method: India Standard Shipping
- Zone: India Shipping Zone
- Countries in zone: India
- Shipping rate: ₹50.0 INR
- Products with shipping category: 53
- Store currency: INR
```

---

## Testing the Fix

### Verify in Console

```ruby
# 1. Get order and package
order = Spree::Order.last
package = order.shipments.first.to_package

# 2. Check available methods
methods = package.shipping_methods
  .available_to_store(order.store)
  .available_for_address(order.ship_address)

puts "Available methods: #{methods.count}"  # Should be > 0
methods.each { |m| puts "  - #{m.name}" }

# 3. Calculate rates
rates = Spree::Stock::Estimator.new.shipping_rates(package)
puts "Calculated rates: #{rates.count}"
rates.each { |r| puts "  - #{r.name}: ₹#{r.cost}" }
```

### Test Through API

```bash
# Update order with India address
curl -X PATCH 'http://localhost:3000/api/checkouts/R708360513' \
  -H 'Content-Type: application/json' \
  --data-raw '{
    "order": {
      "ship_address_id": 3,
      "bill_address_id": 8
    }
  }'

# Advance to delivery (should calculate rates)
curl -X PUT 'http://localhost:3000/api/checkouts/R708360513/next'

# Expected response includes:
{
  "shipments": [{
    "shipping_rates": [{
      "name": "India Standard Shipping",
      "cost": "50.0",
      "selected": true
    }]
  }]
}
```

---

## Key Learnings

### 1. Order of Operations Matters

**Wrong:**
```ruby
method = ShippingMethod.create!(name: "...")  # ❌ Fails validation
method.shipping_categories << category
```

**Right:**
```ruby
method = ShippingMethod.new(name: "...")
method.shipping_categories << category  # Add first
method.calculator = Calculator.new     # Add calculator
method.save!  # ✅ Now validates
```

### 2. All Pieces Must Connect

```
Product → has shipping_category
          ↓
ShippingMethod → has shipping_category (must match!)
                → has zone
                → has calculator
                → has store
                ↓
Zone → has country (must include address country!)
```

**Missing ANY link = No shipping rates!**

### 3. Currency Must Match

```ruby
Order.currency == Calculator.preferences[:currency]
# OR
Calculator.preferences[:currency].blank?  # Works with any currency
```

### 4. Validations Block Save

ShippingMethod requires:
- ✅ At least one shipping category
- ✅ Calculator present
- ✅ Name present

Add these BEFORE calling `save!`

---

## Quick Reference Commands

### Create India Shipping Setup

```bash
rails runner db/seeds/setup_india_shipping.rb
```

### Check Configuration

```ruby
# In console
method = Spree::ShippingMethod.find_by(name: "India Standard Shipping")

puts "Zones: #{method.zones.map(&:name)}"
puts "Countries: #{method.zones.flat_map(&:countries).map(&:name)}"
puts "Calculator: #{method.calculator&.class&.name}"
puts "Rate: ₹#{method.calculator&.preferences&.dig(:amount)}"
puts "Currency: #{method.calculator&.preferences&.dig(:currency)}"
puts "Categories: #{method.shipping_categories.map(&:name)}"
puts "Stores: #{method.stores.map(&:name)}"
```

### Manual Fix for Existing Method

```ruby
# Get the US shipping method
us_method = Spree::ShippingMethod.find_by(name: "UPS Ground (USD)")

# Create India zone
india_zone = Spree::Zone.create!(name: "India")
india = Spree::Country.find(105)
india_zone.zone_members.create!(zoneable: india)

# Add zone to method
us_method.zones << india_zone

# Update calculator currency
us_method.calculator.update!(
  preferences: {
    amount: us_method.calculator.preferences[:amount],
    currency: "INR"  # Change to INR
  }
)

# Rename method
us_method.update!(name: "Standard Shipping")
```

---

## Error Messages and Solutions

### "We are unable to calculate shipping rates"

**Cause:** `shipping_methods(package)` returned `[]`

**Debug:**
```ruby
package.shipping_methods.count  # Start here
package.shipping_methods.available_to_store(store).count  # Filter 1
package.shipping_methods.available_to_store(store)
  .available_for_address(address).count  # Filter 2 ← Usually fails here
```

**Solution:** Add address's country to a zone, associate that zone with shipping method

### "Cannot transition state via :next from :address"

**Cause:** `ensure_available_shipping_rates` validation failed

**Location:** `app/models/spree/order.rb` (line 834-840)

```ruby
def ensure_available_shipping_rates
  if shipments.empty? || shipments.any? { |s| s.shipping_rates.blank? }
    errors.add(:base, "We are unable to calculate shipping rates")
    return false
  end
end
```

**Solution:** Fix shipping configuration so rates are calculated

---

## Related Files

- **Controllers:**
  - `app/controllers/spree/api/checkouts_controller.rb` - API checkout endpoints
  
- **Models:**
  - `app/models/spree/order.rb` - Order state machine
  - `app/models/spree/shipping_method.rb` - Shipping method configuration
  - `app/models/spree/stock/estimator.rb` - Rate calculation
  - `app/models/spree/stock/simple_coordinator.rb` - Shipment creation
  - `app/models/spree/core/state_machines/order/class_methods.rb` - State transitions
  
- **Scripts:**
  - `db/seeds/setup_india_shipping.rb` - India shipping setup

---

**Created:** October 25, 2025  
**Topic:** Solidus Shipping Configuration and Debugging  
**Context:** Setting up India-specific shipping for INR orders



