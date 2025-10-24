# Address System Q&A

Questions and answers about Solidus address management, associations, and historical data preservation.

---

## Table of Contents
1. [Why UserAddress Join Table?](#1-why-useraddress-join-table)
2. [Address Immutability and Sharing](#2-address-immutability-and-sharing)
3. [Historical Data Management](#3-historical-data-management)
4. [Lambda Scopes in Associations](#4-lambda-scopes-in-associations)
5. [Multiple Scopes in Associations](#5-multiple-scopes-in-associations)
6. [Source in Through Associations](#6-source-in-through-associations)
7. [Foreign Key vs Source](#7-foreign-key-vs-source)

---

## 1. Why UserAddress Join Table?

**Q: I created an address using `create_address` action. The address was created (ID: 4), but `UserAddress` table is nil, so the `addresses` action returns empty. What's the issue?**

**A:** When you use `current_user.addresses.build(address_params)`, you only create the `Spree::Address` record, not the join record in `Spree::UserAddress` that links the user to the address.

**Solution:** Use Solidus's `save_in_address_book` method:

```ruby
def create_address
  @address = current_user.save_in_address_book(
    address_params,
    false,      # default = false (set to true if this should be default)
    :shipping   # address_type (:shipping or :billing)
  )
  
  if @address&.persisted?
    render json: @address.as_json, status: :created
  else
    render json: { errors: @address&.errors&.full_messages || ["Invalid address"] }, status: :unprocessable_entity
  end
end
```

**Why this works:**
- `save_in_address_book` creates both the `Spree::Address` and `Spree::UserAddress` records
- It handles de-duplication (reuses existing addresses with same values)
- It manages default address logic automatically

---

## 2. Address Immutability and Sharing

**Q: What does "immutable and shared" mean for addresses? Where is the table set to be immutable?**

### Where Immutability is Enforced

In `app/models/spree/address.rb`:

```ruby
# Lines 127-129
def readonly?
  persisted?  # Once saved to DB, address becomes read-only
end
```

Once an address is saved, you **cannot** update or destroy it. Any attempt will fail.

### What "Shared" Means

Multiple users can point to the **same address record**. The `Address.factory` method (line 43-46) implements this:

```ruby
def self.factory(attributes)
  full_attributes = value_attributes(column_defaults, new(attributes).attributes)
  find_or_initialize_by(full_attributes)  # ← If address exists, reuse it!
end
```

If two users have identical addresses, they share the same `Spree::Address` record.

### Design Benefits

```
Without this pattern (BAD):
Order 1 (Jan):  123 Main St, NYC  (ID: 1)
Order 2 (Feb):  123 Main St, NYC  (ID: 2)  ← Duplicate!
Order 3 (Mar):  123 Main St, NYC  (ID: 3)  ← Duplicate!

With this pattern (GOOD):
Spree::Address (ID: 42) → "123 Main St, NYC"  ← ONE record

Spree::UserAddress:
  - User 1 → Address 42
  - User 2 → Address 42

Spree::Order:
  - Order 1 (ship_address_id: 42)
  - Order 2 (ship_address_id: 42)
```

**Problems Solved:**
1. ✅ **Historical Accuracy**: Old orders keep original address even if user moves
2. ✅ **Storage Efficiency**: No duplicate address data
3. ✅ **Data Consistency**: One source of truth per unique address
4. ✅ **Billing ≠ Shipping**: Join table stores which is default for what purpose

---

## 3. Historical Data Management

**Q: In an interview, I was asked "How do you handle historical data?" I said "save data and reuse if same record is referenced." I believe the solution has more layers. Can you explain?**

### The 5 Layers of Historical Data Management

#### Layer 1: Deduplication ♻️
**Basic reuse to avoid duplicates**

```ruby
Address.find_or_create_by(address1: "123 Main St", city: "NYC")
```

#### Layer 2: Immutability 🔒
**Once created, records never change**

```ruby
# BAD (Mutable):
user.address.update(city: "Boston")  # ❌ Corrupts historical data!
old_order.ship_address.city  # => "Boston" (WRONG! Was NYC)

# GOOD (Immutable):
user.address.update(city: "Boston")  # ❌ Fails! Address is readonly
new_address = Address.create!(city: "Boston")  # ✅ Create new record
old_order.ship_address.city  # => "NYC" (CORRECT!)
```

#### Layer 3: Snapshots 📸
**Copy volatile data at transaction time**

```ruby
# spree_line_items table
t.decimal "price"       # ← Snapshot of price at order time
t.decimal "cost_price"  # ← Snapshot of cost at order time

# Even if product.price changes, order shows what customer actually paid
line_item.price  # => 100 (what they paid in January)
variant.price    # => 150 (current price in June)
```

#### Layer 4: Temporal Versioning 📅
**Track state transitions with timestamps**

```ruby
# spree_state_changes table
Order #123 State Changes:
  1. cart      → address   (2024-01-01 10:00, user: customer)
  2. address   → delivery  (2024-01-01 10:15, user: customer)
  3. delivery  → payment   (2024-01-01 10:20, user: customer)
  4. payment   → complete  (2024-01-01 10:25, user: customer)
  5. complete  → canceled  (2024-01-02 09:00, user: admin)
```

#### Layer 5: Audit Logs 📝
**Track who changed what, when, and why**

```ruby
# Using gems like PaperTrail
product.versions.last
# => {
#   event: "update",
#   whodunnit: "admin@example.com",
#   created_at: "2024-01-15",
#   changeset: { name: ["Old Name", "New Name"], price: [100, 50] }
# }
```

### Interview Answer Template

**Why:** "Historical data preservation is critical for business compliance, auditing, and accurate reporting."

**Layers:**
1. **Deduplication**: Avoid duplicates where possible
2. **Immutability**: Make transactional data read-only after creation
3. **Snapshots**: Copy volatile data (like prices) at transaction time
4. **Temporal Versioning**: Track state transitions with timestamps
5. **Audit Logging**: Full change tracking with who/what/when

**Example:** "When a customer moves, we create a NEW address record rather than updating the old one. Old orders still point to the NYC address, new orders use the Boston address. This preserves exactly what happened during each transaction."

**Trade-offs:** "More storage space, but essential for data integrity, compliance, and preventing data corruption."

---

## 4. Lambda Scopes in Associations

**Q: Why is there a lambda in this association?**

```ruby
has_one :default_user_ship_address, ->{ default_shipping }, 
        class_name: 'Spree::UserAddress', 
        foreign_key: 'user_id'
```

### What the Lambda Does

The lambda `->{ default_shipping }` adds a **scope (filter)** to the association.

In `Spree::UserAddress`:
```ruby
scope :default_shipping, -> { where(default: true) }
```

**SQL Generated:**
```sql
SELECT * FROM spree_user_addresses 
WHERE user_id = ? 
  AND default = true  -- ← Added by the lambda!
LIMIT 1
```

### Without vs With Lambda

```ruby
# WITHOUT lambda (wrong):
has_one :default_user_ship_address, class_name: 'Spree::UserAddress'
# Returns: ANY UserAddress (first one, random)

# WITH lambda (correct):
has_one :default_user_ship_address, ->{ default_shipping }, class_name: 'Spree::UserAddress'
# Returns: ONLY UserAddress where default = true
```

### Why Lambda Syntax?

**Lazy Evaluation**: The scope is evaluated when accessed, not at class load time.

```ruby
# BAD (evaluated at class load time):
has_one :recent, where('created_at > ?', 1.day.ago)  # ❌ Time is frozen!

# GOOD (evaluated at query time):
has_one :recent, ->{ where('created_at > ?', 1.day.ago) }  # ✅ Current time!
```

---

## 5. Multiple Scopes in Associations

**Q: Can we pass extra scopes in associations?**

**A:** Yes! You can add multiple scopes and conditions.

### Examples

#### Single Scope
```ruby
has_one :default_user_ship_address, ->{ default_shipping }, 
        class_name: 'Spree::UserAddress'
```

#### Multiple Chained Scopes
```ruby
has_many :recent_active_orders, 
         ->{ complete.where('created_at > ?', 1.month.ago).order(created_at: :desc) },
         class_name: 'Spree::Order'
```

#### Multiple Named Scopes
```ruby
has_many :recent_active_default_addresses,
         ->{ default_shipping.active.recent },
         class_name: 'Spree::UserAddress'
```

#### Real Examples from Solidus

```ruby
# From variant.rb
has_many :images, ->{ order(:position) }, as: :viewable, class_name: "Spree::Image"

# From shipment.rb
has_many :shipping_rates, ->{ order(:cost) }, dependent: :destroy
has_many :cartons, ->{ distinct }, through: :inventory_units
```

### Available Query Methods

Inside the lambda, you can use:
- `where` - Filter
- `order` - Sort
- `limit` / `offset` - Pagination
- `distinct` - Remove duplicates
- `includes` / `joins` - Eager loading
- `group` / `having` - Aggregation
- `select` - Specific columns

---

## 6. Source in Through Associations

**Q: What is `source` in this association?**

```ruby
has_one :ship_address, through: :default_user_ship_address, source: :address
```

### What `source` Does

`source` tells Rails **which association to follow** on the intermediate model.

### The Chain

```ruby
User
  ↓ has_one :default_user_ship_address
UserAddress (has belongs_to :address)
  ↓ source: :address (follow THIS association)
Address
```

### Why It's Needed

The association name on User (`:ship_address`) doesn't match the association name on UserAddress (`:address`).

```ruby
# UserAddress model has:
belongs_to :address  # ← Called :address

# User wants to call it:
has_one :ship_address  # ← Different name!

# So we use source to map them:
has_one :ship_address, through: :default_user_ship_address, source: :address
#       ^^^^^^^^^^^^^                                              ^^^^^^^
#       Your name                                                  Original name
```

### When Source is NOT Needed

If names match, Rails auto-detects:

```ruby
class Order
  has_many :line_items
end

class User
  has_many :line_items, through: :orders
  # No source needed! Rails finds :line_items on Order automatically
end
```

### SQL Generated

```ruby
user.ship_address

# SQL:
# SELECT addresses.* 
# FROM addresses
# INNER JOIN user_addresses 
#   ON addresses.id = user_addresses.address_id
# WHERE user_addresses.user_id = 1
#   AND user_addresses.default = true
# LIMIT 1
```

---

## 7. Foreign Key vs Source

**Q: Instead of `source`, can we give `foreign_key`?**

**A:** No, they serve different purposes:

### foreign_key
- Specifies which **database column** to use for the join
- Used in direct associations (`belongs_to`, `has_many`)

```ruby
has_many :user_addresses, foreign_key: "user_id"
# Uses 'user_id' column in user_addresses table
```

### source
- Specifies which **association** to follow on the intermediate model
- Used in `through` associations

```ruby
has_one :ship_address, through: :default_user_ship_address, source: :address
# Follow the :address association on UserAddress
```

### They Work Together

```ruby
# Direct association uses foreign_key:
has_one :default_user_ship_address, 
        foreign_key: "user_id",  # ← Which column in user_addresses
        class_name: 'Spree::UserAddress'

# Through association uses source:
has_one :ship_address, 
        through: :default_user_ship_address,  # ← Which intermediate association
        source: :address                       # ← Which association to follow
```

**Key Difference:**
- `foreign_key` = Database column name
- `source` = Association name

---

## Key Architecture Patterns

### Address Management Pattern

```
┌─────────────────────────────────────────────────┐
│ Spree::User                                      │
├─────────────────────────────────────────────────┤
│ has_many :user_addresses                         │
│ has_many :addresses, through: :user_addresses    │
│                                                  │
│ has_one :default_user_ship_address, ->{ ... }   │
│ has_one :ship_address, through: ..., source: .. │
│                                                  │
│ has_one :default_user_bill_address, ->{ ... }   │
│ has_one :bill_address, through: ..., source: .. │
└──────────────────┬──────────────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────────────┐
│ Spree::UserAddress (Join Table)                 │
├─────────────────────────────────────────────────┤
│ user_id (FK)                                     │
│ address_id (FK)                                  │
│ default (boolean) - default shipping?            │
│ default_billing (boolean) - default billing?     │
│ archived (boolean)                               │
│ created_at, updated_at                           │
├─────────────────────────────────────────────────┤
│ belongs_to :user                                 │
│ belongs_to :address                              │
└──────────────────┬──────────────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────────────┐
│ Spree::Address (Immutable, Shared)              │
├─────────────────────────────────────────────────┤
│ name, address1, address2, city, zipcode          │
│ country_id, state_id, phone                      │
│                                                  │
│ readonly? returns true if persisted             │
│                                                  │
│ self.factory - finds or creates unique address  │
└─────────────────────────────────────────────────┘
```

### Association Methods Summary

| Method | Purpose | Example |
|--------|---------|---------|
| `class_name` | Specify model class | `class_name: 'Spree::UserAddress'` |
| `foreign_key` | Specify database column | `foreign_key: 'user_id'` |
| `through` | Go through intermediate | `through: :user_addresses` |
| `source` | Which association to follow | `source: :address` |
| `->{ scope }` | Add query conditions | `->{ where(default: true) }` |
| `dependent` | What happens on destroy | `dependent: :destroy` |
| `inverse_of` | Specify reverse association | `inverse_of: :user` |

---

## Practical Usage Examples

### Creating an Address

```ruby
# ❌ WRONG: Only creates Address, not UserAddress
address = current_user.addresses.build(address_params)
address.save

# ✅ CORRECT: Creates both Address and UserAddress
address = current_user.save_in_address_book(
  address_params,
  false,      # Make it default?
  :shipping   # Address type
)
```

### Accessing Addresses

```ruby
user = Spree::User.first

# All addresses
user.addresses

# All UserAddress join records
user.user_addresses

# Default shipping address
user.ship_address

# Default billing address
user.bill_address

# Default shipping UserAddress (with metadata)
user.default_user_ship_address
```

### Setting Default Addresses

```ruby
# Mark address as default shipping
user.mark_default_ship_address(address)

# Mark address as default billing
user.mark_default_bill_address(address)

# Or during creation
user.save_in_address_book(params, true, :shipping)  # true = make default
```

---

## References

- **Models:**
  - `app/models/spree/address.rb`
  - `app/models/spree/user_address.rb`
  - `app/models/concerns/spree/user_address_book.rb`

- **Controllers:**
  - `app/controllers/api/users_controller.rb`

- **Database:**
  - `db/schema.rb` - Tables: `spree_addresses`, `spree_user_addresses`

- **Related Documentation:**
  - `RAILS_CALLBACKS_AND_LIFECYCLE_QA.md`
  - `PREFERENCE_SYSTEM_QA_AND_EXERCISES.md`

