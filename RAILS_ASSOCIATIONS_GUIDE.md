# Rails Associations Guide

## 1. The `inverse_of` Option

### What It Does

Tells Rails that two associations point to each other, ensuring both sides use the **same object in memory**.

### Example

```ruby
# tax_rate.rb
has_many :tax_rate_tax_categories,
  class_name: 'Spree::TaxRateTaxCategory',
  inverse_of: :tax_rate  # ← Points to belongs_to on other side

# tax_rate_tax_category.rb
belongs_to :tax_rate,
  class_name: 'Spree::TaxRate',
  inverse_of: :tax_rate_tax_categories  # ← Points to has_many on other side
```

### Benefits

**Without `inverse_of`:**
```ruby
tax_rate = TaxRate.first
join = tax_rate.tax_rate_tax_categories.first
parent = join.tax_rate

tax_rate.object_id  # => 12345
parent.object_id    # => 67890  ❌ Different objects!

tax_rate.name = "Updated"
join.tax_rate.name  # ❌ Still old value (different object)
```

**With `inverse_of`:**
```ruby
tax_rate = TaxRate.first
join = tax_rate.tax_rate_tax_categories.first
parent = join.tax_rate

tax_rate.object_id  # => 12345
parent.object_id    # => 12345  ✅ Same object!

tax_rate.name = "Updated"
join.tax_rate.name  # ✅ "Updated" (same object)
```

### When Required

| Scenario | Need inverse_of? |
|----------|------------------|
| Using `class_name` | ✅ YES |
| Simple associations (no class_name) | ❌ NO (auto-detected) |
| Reverse association not defined | ❌ NO (nothing to inverse) |

---

## 2. Namespacing and `class_name`

### The Problem

When models are in a namespace, Rails can't find them by association name alone.

```ruby
# Without namespace
class TaxRate < ApplicationRecord
  has_many :tax_categories  # Rails finds TaxCategory ✅
end

# With namespace
module Spree
  class TaxRate < ApplicationRecord
    has_many :tax_categories  # Rails looks for TaxCategory (not Spree::TaxCategory) ❌
  end
end
```

### The Solution

```ruby
module Spree
  class TaxRate < ApplicationRecord
    has_many :tax_categories,
      class_name: 'Spree::TaxCategory'  # ✅ Explicit namespace
  end
end
```

### When `class_name` is Required

- Models in a namespace (module) → ✅ REQUIRED
- Association name differs from model → ✅ REQUIRED
- Models in root namespace → ❌ NOT REQUIRED

### Why `inverse_of` Follows

When you use `class_name`, you MUST add `inverse_of` because Rails can't auto-detect the reverse association.

```ruby
module Spree
  class TaxRate < ApplicationRecord
    has_many :tax_rate_tax_categories,
      class_name: 'Spree::TaxRateTaxCategory',  # ← Forces inverse_of
      inverse_of: :tax_rate                      # ← Must specify
  end
end
```

---

## 3. Explicit Association vs Skipping It

### Key Insight

**`belongs_to` is always required** (on the side with foreign key).

**`has_many` is optional** - only define if you need to navigate that direction.

### Example: LineItem and TaxCategory

```ruby
# LineItem MUST define belongs_to (has foreign key)
class LineItem < ApplicationRecord
  belongs_to :tax_category,
    class_name: 'Spree::TaxCategory',
    optional: true
end

# TaxCategory can SKIP has_many (not used in business logic)
class TaxCategory < ApplicationRecord
  # ❌ NO has_many :line_items defined
  # Business logic doesn't need tax_category.line_items
end
```

### What You Can Still Do Without `has_many`

```ruby
# Query with ActiveRecord
LineItem.where(tax_category: tax_category)

# Count
LineItem.where(tax_category: tax_category).count

# Check existence
LineItem.exists?(tax_category: tax_category)
```

### What You Can't Do Without `has_many`

```ruby
tax_category.line_items           # ❌ NoMethodError
tax_category.line_items.build     # ❌ NoMethodError
tax_category.line_items.count     # ❌ NoMethodError
```

### When to Define `has_many`

| Use Case | Define has_many? |
|----------|------------------|
| You use `parent.children` in code | ✅ YES |
| Need `dependent: :destroy` | ✅ YES |
| Use nested attributes | ✅ YES |
| Never navigate that direction | ❌ NO |
| Only use ActiveRecord queries | ❌ NO |

---

## 4. has_many :through - Both Sides Required

For `has_many :through`, you MUST define BOTH associations:

```ruby
class TaxRate < ApplicationRecord
  # 1. Join model association - REQUIRED
  has_many :tax_rate_tax_categories,
    class_name: 'Spree::TaxRateTaxCategory'
  
  # 2. Final model association - REQUIRED
  has_many :tax_categories,
    through: :tax_rate_tax_categories,
    class_name: 'Spree::TaxCategory'
end
```

**You cannot skip either one!**

---

## Summary Table

| Concept | When Required | When Optional |
|---------|---------------|---------------|
| `belongs_to` | ✅ ALWAYS | ❌ NEVER |
| `has_many` | When you use `parent.children` | When you only query via ActiveRecord |
| `class_name` | Models in namespace | Models in root namespace |
| `inverse_of` | When using `class_name` | Simple associations (auto-detected) |
| Both sides of `:through` | ✅ ALWAYS (join + final) | ❌ NEVER |

---

## Quick Examples

### Minimal (No Namespace)

```ruby
class Post < ApplicationRecord
  has_many :comments
end

class Comment < ApplicationRecord
  belongs_to :post
end
```

### With Namespace (Needs class_name + inverse_of)

```ruby
module Spree
  class Order < ApplicationRecord
    has_many :line_items,
      class_name: 'Spree::LineItem',
      inverse_of: :order
  end
  
  class LineItem < ApplicationRecord
    belongs_to :order,
      class_name: 'Spree::Order',
      inverse_of: :line_items
  end
end
```

### Skipping Reverse (When Not Needed)

```ruby
# LineItem needs the association
class LineItem < ApplicationRecord
  belongs_to :tax_category
end

# TaxCategory doesn't define has_many (not used)
class TaxCategory < ApplicationRecord
  # Skipped: has_many :line_items
end
```

---

**Key Takeaway:** Define what you use, skip what you don't. Rails requires `belongs_to` always, but `has_many` is optional if you never navigate that direction!

