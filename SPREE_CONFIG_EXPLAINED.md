# Spree::Config.roles - The Full Story

## The Question

Why is `Spree::Config.roles` a `RoleConfiguration` object? Is there an alias?

---

## The Answer

**No alias!** It's a **getter method** defined in `Spree::AppConfiguration` that returns a `RoleConfiguration` instance.

---

## The Chain

```
Spree::Config
  ↓ (is an instance of)
Spree::AppConfiguration
  ↓ (has a method)
def roles
  @roles ||= RoleConfiguration.new
end
  ↓ (returns)
RoleConfiguration instance
```

---

## The Code

**File: `app/models/spree/app_configuration.rb`** ← NOW AT APPLICATION LEVEL!

```ruby
module Spree
  class AppConfiguration
    # ... lots of preference settings ...
    
    # This is the method that returns a RoleConfiguration object!
    def roles
      @roles ||= Spree::RoleConfiguration.new.tap do |roles|
        # Default role configuration
        roles.assign_permissions :default, ['Spree::PermissionSets::DefaultCustomer']
        roles.assign_permissions :admin, ['Spree::PermissionSets::SuperUser']
      end
    end
  end
end
```

**What this does:**

1. **Memoization**: Uses `@roles ||=` to cache the `RoleConfiguration` instance
2. **Initialization**: Creates a new `RoleConfiguration` object
3. **Default Setup**: Assigns default permissions:
   - `:default` role → `DefaultCustomer` permission set
   - `:admin` role → `SuperUser` permission set
4. **Returns**: The configured `RoleConfiguration` object

---

## How Spree::Config Works

**File: `solidus_core/lib/spree.rb`** (in the gem)

```ruby
module Spree
  class << self
    def config
      @config ||= Spree::AppConfiguration.new
    end
    
    alias :Config :config
  end
end
```

So:
- `Spree.config` returns a **singleton instance** of `AppConfiguration`
- `Spree::Config` is an **alias** for `Spree.config`
- Both are the same object!

---

## The Complete Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ config/initializers/spree.rb                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Spree.config do |config|                                       │
│    config.roles.assign_permissions :customer, [...]             │
│  end                                                            │
│                                                                 │
│  Let's break down: config.roles                                │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: What is `config`?                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  config = Spree::AppConfiguration instance                      │
│  (created by Spree.config method)                               │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: What is `config.roles`?                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Calls the `roles` method on AppConfiguration:                  │
│                                                                 │
│  def roles                                                      │
│    @roles ||= RoleConfiguration.new.tap do |roles|             │
│      roles.assign_permissions :default, [...]                   │
│      roles.assign_permissions :admin, [...]                     │
│    end                                                          │
│  end                                                            │
│                                                                 │
│  Returns: RoleConfiguration instance (memoized)                 │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: What is `RoleConfiguration`?                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  A class that maps role names to permission sets                │
│  Now at: app/models/spree/core/role_configuration.rb           │
│                                                                 │
│  Methods:                                                       │
│  - assign_permissions(role_name, permission_sets)               │
│  - activate_permissions!(ability, user)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why It's Named `roles`

The method is named `roles` because:
1. It manages the **configuration for roles**
2. It returns an object that **maps roles to permissions**
3. Semantic clarity: `config.roles` reads nicely

**It's NOT:**
- A list of roles (that's `Spree::Role.all`)
- A single role (that's `Spree::Role.find_by(name: 'customer')`)

**It IS:**
- The **configuration object** that defines what permissions each role gets

---

## Real-World Usage

```ruby
# In config/initializers/spree.rb

Spree.config do |config|
  # `config` is an AppConfiguration instance
  # `config.roles` calls the `roles` method
  # which returns a RoleConfiguration instance
  # on which we call `assign_permissions`
  
  config.roles.assign_permissions :customer, ['Spree::PermissionSets::DefaultCustomer']
  #      ↑                          ↑                         ↑
  #      |                          |                         |
  #  RoleConfiguration         Role name              Permission set class
  #     instance
end

# Later, when authorize! is called:

# 1. Spree::Ability.new(user) is created
# 2. Calls activate_permission_sets
# 3. Which calls: Spree::Config.roles.activate_permissions!(ability, user)
#                              ↑
#                              |
#                   Gets the RoleConfiguration instance
#                   and calls activate_permissions! on it
```

---

## The Aliases in Spree

There's **ONE alias** in Spree config:

```ruby
module Spree
  class << self
    def config
      @config ||= AppConfiguration.new
    end
    
    alias :Config :config  # ← This is the only alias!
  end
end
```

So these are identical:
```ruby
Spree.config.roles      # Using the method name
Spree::Config.roles     # Using the alias (capitalized)
```

**But `roles` itself is NOT an alias!** It's just a getter method.

---

## Summary Table

| What | Type | What It Is |
|------|------|------------|
| `Spree.config` | Method | Returns singleton `AppConfiguration` instance |
| `Spree::Config` | Alias | Alias for `Spree.config` |
| `Spree::AppConfiguration` | Class | Configuration class with all Spree settings |
| `config.roles` | Method | Returns `RoleConfiguration` instance |
| `RoleConfiguration` | Class | Maps role names to permission sets |
| `@roles` | Instance variable | Cached `RoleConfiguration` instance |

---

## Key Insight

```ruby
Spree::Config.roles
#       ↑      ↑
#       |      |
#    Alias   Method (returns RoleConfiguration)
```

**The naming:**
- `Config` = Capitalized alias for `config` method
- `roles` = Method name (not an alias!)
- Returns `RoleConfiguration` object

**Why not `Spree::Config.role_configuration`?**
- Shorter, cleaner API
- Reads naturally: "config for roles"
- Common Rails pattern (like `config.cache_store`, `config.action_mailer`)

---

## Why AppConfiguration is Now at Application Level

**File: `app/models/spree/app_configuration.rb`** (743 lines)

Now that `AppConfiguration` is at your application level, you can:

### **1. Customize the `roles` Method**

```ruby
def roles
  @roles ||= Spree::RoleConfiguration.new.tap do |roles|
    roles.assign_permissions :default, ['Spree::PermissionSets::DefaultCustomer']
    roles.assign_permissions :admin, ['Spree::PermissionSets::SuperUser']
    
    # Add your custom roles here!
    roles.assign_permissions :manager, [
      'Spree::PermissionSets::OrderManagement',
      'Spree::PermissionSets::ProductManagement'
    ]
  end
end
```

### **2. Change Default Preferences**

```ruby
# Change defaults directly in the class
preference :allow_guest_checkout, :boolean, default: false  # Was true

preference :admin_products_per_page, :integer, default: 50  # Was 10
```

### **3. Add Custom Preferences**

```ruby
# Add your own preferences
preference :enable_custom_feature, :boolean, default: true
preference :max_items_per_order, :integer, default: 100
preference :api_rate_limit, :integer, default: 1000

# Then use them:
# Spree::Config.enable_custom_feature
# Spree::Config.max_items_per_order
```

### **4. Add Custom Methods**

```ruby
def custom_payment_methods
  @custom_payment_methods ||= PaymentMethod.where(active: true)
end

def custom_shipping_calculator
  # Your custom logic
end
```

### **5. Override Environment Methods**

```ruby
# Add custom environment configurations
environment.define do
  add_class :custom_service
  add_class :custom_calculator
end
```

---

**Bottom Line:** `Spree::Config.roles` is a **method** (not an alias) that returns a **`RoleConfiguration`** instance. The method is named `roles` because it manages role configuration, following Rails conventions for configuration methods.

Now that **both** `AppConfiguration` and `RoleConfiguration` are at application level, you have complete control over Spree's configuration system!

