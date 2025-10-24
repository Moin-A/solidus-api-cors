# Rails Configuration & Model Decoration Patterns

## 1. Rails.application.config

**What it is:**
- A configuration object for your Rails application
- Holds all application-wide settings
- Available globally throughout your app's lifecycle

**Common Uses:**

```ruby
# config/application.rb or config/environments/development.rb

# Framework settings
Rails.application.config.time_zone = 'UTC'
Rails.application.config.eager_load = false
Rails.application.config.active_job.queue_adapter = :sidekiq
Rails.application.config.action_mailer.delivery_method = :smtp

# Custom configuration (use .x namespace)
Rails.application.config.x.payment_gateway = 'stripe'
Rails.application.config.x.api_key = ENV['API_KEY']
```

**Accessing Configuration:**

```ruby
# Anywhere in your app
Rails.application.config.time_zone
# or
Rails.configuration.time_zone

# Custom configs
Rails.application.config.x.payment_gateway
```

**Key Difference:**
- `Rails.application.config` = Framework-level (Rails itself)
- `Spree.config` = Application-level (Spree/Solidus specific)

---

## 2. Rails.application.config.to_prepare

**What it does:**
- A callback hook that runs code at specific times
- **Development:** Runs before EVERY request (because code reloads)
- **Production:** Runs ONCE at application startup (no code reloading)

**Why it's needed:**

In development, Rails reloads your code between requests. If you set up something in an initializer that references code that gets reloaded, it can break. `to_prepare` ensures your setup runs after code reloading.

**When to use:**

```ruby
# config/initializers/spree.rb

# ❌ WRONG - Don't do this for decorators
Spree::Product.include MyProductExtensions
# This breaks in development because Spree::Product reloads but your extension doesn't

# ✅ CORRECT - Use to_prepare
Rails.application.config.to_prepare do
  # Code here runs after every code reload in development
  # and once at startup in production
  
  # Decorators
  Spree::Product.include MyProductExtensions
  Spree::ProductsController.prepend MyProductsControllerOverrides
  
  # Dynamic configuration
  Spree.config do |config|
    config.stock_location_sorter_class = 'CustomStockLocationSorter'
  end
  
  # Event subscribers
  Spree::Event.subscribe 'order_finalized' do |event|
    OrderNotificationJob.perform_later(event.payload[:order].id)
  end
end
```

**Rule of thumb:**
- Static configs → `Rails.application.config`
- Code that references app classes → `Rails.application.config.to_prepare`

---

## 3. Model Decoration Patterns

### Overview

When you need to customize a gem's model (like Spree::User), you have several approaches:

| Method | Precedence | Use Case |
|--------|-----------|----------|
| `class_eval` | Reopens class | Simple additions/replacements |
| Module + `include` | After class | Adding new methods only |
| Module + `prepend` | Before class | Wrapping/decorating existing methods |

---

### Pattern 1: Using `prepend` (Recommended for decorating)

**When to use:**
- ✅ Wrapping existing methods with custom logic
- ✅ You want to call the original method with `super`
- ✅ Complex overrides
- ✅ Recommended by Solidus/Spree

**How it works:**

```ruby
# app/models/spree/user_decorator.rb
module Spree
  module UserDecorator
    # Override method - your code runs FIRST
    def confirm
      Rails.logger.info "Confirming user: #{email}"
      
      # Call original method
      result = super
      
      # Your code after original
      if result
        send_welcome_email
        track_confirmation
      end
      
      result
    end
    
    # Add new methods
    def resend_confirmation_with_limit
      return false if confirmation_sent_count >= 3
      send_confirmation_instructions
    end
    
    # Class-level additions
    def self.prepended(base)
      base.scope :unconfirmed, -> { where(confirmed_at: nil) }
      base.validates :terms_accepted, acceptance: true
      base.after_confirmation :send_welcome_email
    end
    
    private
    
    def send_welcome_email
      UserMailer.welcome_email(self).deliver_later
    end
    
    def track_confirmation
      AnalyticsService.track(user_id: id, event: 'confirmed')
    end
  end
end

# config/initializers/spree.rb
Rails.application.config.to_prepare do
  Spree::User.prepend Spree::UserDecorator
end
```

**Ancestor chain with prepend:**

```ruby
Spree::User.ancestors
# => [UserDecorator, Spree::User, Devise::Models::Confirmable, ...]
#     ↑ First         ↑ Second (super goes here)
```

**Method lookup flow:**

```
user.confirm called
↓
UserDecorator#confirm (your code before super)
↓
super called
↓
Spree::User#confirm (original Devise code)
↓
Returns to UserDecorator#confirm (your code after super)
↓
Returns result
```

---

### Pattern 2: Using `include` (For adding new methods)

**When to use:**
- ✅ Adding completely new methods
- ❌ NOT for overriding existing methods (doesn't work well)

**How it works:**

```ruby
module Spree
  module UserExtensions
    # Add new methods
    def full_name
      "#{firstname} #{lastname}"
    end
    
    def premium_member?
      subscriptions.active.exists?
    end
    
    # This WON'T work as expected for overriding!
    def confirm
      super  # May not call what you expect
    end
  end
end

Rails.application.config.to_prepare do
  Spree::User.include Spree::UserExtensions
end
```

**Ancestor chain with include:**

```ruby
Spree::User.ancestors
# => [Spree::User, UserExtensions, Devise::Models::Confirmable, ...]
#     ↑ First (original method found here, extensions skipped!)
```

**Problem:** If `Spree::User#confirm` exists, it's found first, and your `UserExtensions#confirm` is never called!

---

### Pattern 3: Using `class_eval` (Direct class reopening)

**When to use:**
- ✅ Simple customizations
- ✅ Adding validations, associations, scopes
- ✅ Adding new methods
- ✅ Straightforward syntax
- ⚠️ Replaces methods completely (can't easily call original)

**How it works:**

```ruby
# app/models/spree/user_decorator.rb
Spree::User.class_eval do
  # Add validations
  validates :phone_number, presence: true, if: :confirmed?
  validates :terms_accepted, acceptance: true
  
  # Add associations
  has_many :wishlists, dependent: :destroy
  has_many :reviews, dependent: :nullify
  
  # Add scopes
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :premium, -> { where(premium: true) }
  scope :recently_confirmed, -> { where('confirmed_at > ?', 1.week.ago) }
  
  # Add callbacks
  after_confirmation :send_welcome_email
  after_confirmation :create_default_wishlist
  
  # Add new methods
  def full_name
    "#{firstname} #{lastname}".strip
  end
  
  def resend_confirmation_with_limit
    return false if confirmation_sent_count >= 3
    
    increment!(:confirmation_sent_count)
    send_confirmation_instructions
  end
  
  def confirmation_expired?
    return false if confirmed?
    confirmation_sent_at && confirmation_sent_at < 3.days.ago
  end
  
  # Override existing method (replaces it completely)
  def confirm
    # You must reimplement everything if you override
    # Can still call super, but less clean than prepend
    return false unless valid_for_confirmation?
    
    super  # Calls original
  end
  
  private
  
  def valid_for_confirmation?
    created_at < 1.hour.ago  # Prevent immediate confirmation
  end
  
  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  end
  
  def create_default_wishlist
    wishlists.create(name: 'My Wishlist', default: true)
  end
end

# config/initializers/spree.rb
Rails.application.config.to_prepare do
  require_dependency 'spree/user_decorator'
end
```

**Note:** With `class_eval`, you're reopening the class directly. No module, no prepend needed.

---

## 4. Understanding `super` with Different Patterns

### What `super` does:

**`super` calls the method with the same name in the NEXT class/module in the ancestor chain (moving RIGHT).**

### Example: Ancestor Chain

```ruby
# With prepend
Spree::User.prepend UserDecorator

Spree::User.ancestors
# => [UserDecorator, Spree::User, Devise::Confirmable, Object, Kernel, BasicObject]

# When you call super in UserDecorator#confirm:
# Current: UserDecorator
# super → moves RIGHT → Spree::User#confirm ✅
```

```ruby
# With include
Spree::User.include UserDecorator

Spree::User.ancestors
# => [Spree::User, UserDecorator, Devise::Confirmable, Object, Kernel, BasicObject]

# Problem: Spree::User#confirm is found FIRST
# UserDecorator#confirm never runs! ❌
# If it did run, super would go RIGHT → Devise::Confirmable
```

### Visual Flow with prepend:

```
[UserDecorator, Spree::User, Devise, Object]
 ↑ Start here
 
UserDecorator#confirm runs
↓
Calls super
↓
Moves RIGHT in chain →
↓
Spree::User#confirm runs
↓
Returns to UserDecorator#confirm
↓
Returns final result
```

---

## 5. Comparison: All Three Patterns

### Example: Adding Devise Confirmable customizations

#### Option A: Using `prepend` (Best for wrapping)

```ruby
module Spree
  module UserDecorator
    def confirm
      Rails.logger.info "Before confirm"
      result = super  # Calls original cleanly
      Rails.logger.info "After confirm"
      result
    end
  end
end

Rails.application.config.to_prepare do
  Spree::User.prepend Spree::UserDecorator
end
```

#### Option B: Using `class_eval` (Best for simple additions)

```ruby
Spree::User.class_eval do
  after_confirmation :send_welcome_email
  
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  
  def resend_confirmation_with_limit
    return false if confirmation_sent_count >= 3
    send_confirmation_instructions
  end
  
  private
  
  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  end
end

Rails.application.config.to_prepare do
  require_dependency 'spree/user_decorator'
end
```

#### Option C: Using `include` (Only for new methods)

```ruby
module Spree
  module UserExtensions
    def full_name
      "#{firstname} #{lastname}"
    end
  end
end

Rails.application.config.to_prepare do
  Spree::User.include Spree::UserExtensions
end
```

---

## 6. Recommendation for Devise Confirmable

**For your use case (adding Devise confirmable features), use `class_eval`:**

```ruby
# app/models/spree/user_decorator.rb
Spree::User.class_eval do
  # Callbacks
  after_confirmation :send_welcome_email
  after_confirmation :create_default_address
  
  # Validations
  validates :phone_number, presence: true, if: :confirmed?
  
  # Scopes
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :recently_confirmed, -> { where('confirmed_at > ?', 1.week.ago) }
  
  # Custom methods
  def resend_confirmation_with_limit
    return false if confirmation_sent_count >= 3
    
    increment!(:confirmation_sent_count)
    send_confirmation_instructions
  end
  
  def confirmation_expired?
    return false if confirmed?
    confirmation_sent_at && confirmation_sent_at < 3.days.ago
  end
  
  private
  
  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  end
  
  def create_default_address
    addresses.create(
      firstname: email.split('@').first,
      lastname: 'User',
      address1: 'TBD',
      city: 'TBD',
      zipcode: '000000',
      country: Spree::Country.default,
      phone: '0000000000'
    )
  end
end

# config/initializers/spree.rb
Rails.application.config.to_prepare do
  require_dependency 'spree/user_decorator'
end
```

**Why `class_eval` for this case:**
- Simple and direct
- Perfect for adding callbacks, validations, scopes
- Less boilerplate than module + prepend
- You're mostly adding new behavior, not wrapping existing methods

**Use `prepend` when:**
- You need to wrap around Devise's internal methods
- You want fine-grained control over method execution order
- You're doing complex overrides

---

## Summary Table

| Pattern | Syntax | Use Case | super behavior |
|---------|--------|----------|----------------|
| `prepend` | Module + prepend | Wrapping methods | ✅ Calls original reliably |
| `include` | Module + include | New methods only | ⚠️ Unreliable for overrides |
| `class_eval` | Direct reopening | Simple additions/callbacks | ✅ Works but less modular |

**Golden Rule:**
- Need to wrap/decorate? → `prepend`
- Need simple additions? → `class_eval`
- Only new methods? → `include`

---

## 7. Can We Use to_prepare with class_eval, include, prepend Interchangeably?

**Short answer: YES, but with important differences!**

### The Pattern

All three decoration methods should be wrapped in `to_prepare`:

```ruby
# config/initializers/spree.rb

# Pattern 1: to_prepare + prepend
Rails.application.config.to_prepare do
  Spree::User.prepend Spree::UserDecorator
end

# Pattern 2: to_prepare + include
Rails.application.config.to_prepare do
  Spree::User.include Spree::UserExtensions
end

# Pattern 3: to_prepare + class_eval
Rails.application.config.to_prepare do
  require_dependency 'spree/user_decorator'
  # OR directly:
  # Spree::User.class_eval do
  #   # your code
  # end
end
```

### Why to_prepare is Needed for All Three

**The problem:** In development mode, Rails reloads your application code between requests. This means:

```ruby
# First request
Spree::User.prepend MyDecorator  # Works fine

# Code reloads...

# Second request
# Spree::User class is reloaded (fresh copy)
# But MyDecorator is NOT reloaded
# Result: Spree::User no longer has your decorations! ❌
```

**The solution:** `to_prepare` runs after every code reload:

```ruby
Rails.application.config.to_prepare do
  # This code runs:
  # - After every code reload in development
  # - Once at startup in production
  
  Spree::User.prepend MyDecorator  # ✅ Always applied
end
```

### Comparison: With and Without to_prepare

#### ❌ WITHOUT to_prepare (Breaks in development)

```ruby
# config/initializers/spree.rb

# This runs ONCE when Rails boots
Spree::User.class_eval do
  def custom_method
    "works on first request"
  end
end

# First request: works ✅
# Code reloads...
# Second request: Spree::User.new.custom_method → NoMethodError ❌
```

#### ✅ WITH to_prepare (Works everywhere)

```ruby
# config/initializers/spree.rb

Rails.application.config.to_prepare do
  # This runs after EVERY code reload
  Spree::User.class_eval do
    def custom_method
      "works every time"
    end
  end
end

# First request: works ✅
# Code reloads...
# Second request: works ✅
# Production: works ✅
```

### All Three Patterns Work the Same Way with to_prepare

```ruby
# config/initializers/spree.rb

# ✅ Option 1: prepend
Rails.application.config.to_prepare do
  Spree::User.prepend Spree::UserDecorator
end

# ✅ Option 2: include
Rails.application.config.to_prepare do
  Spree::User.include Spree::UserExtensions
end

# ✅ Option 3: class_eval
Rails.application.config.to_prepare do
  Spree::User.class_eval do
    # your modifications
  end
end

# ✅ Option 4: Multiple decorators
Rails.application.config.to_prepare do
  Spree::User.prepend Spree::UserDecorator
  Spree::Product.prepend Spree::ProductDecorator
  Spree::Order.include Spree::OrderExtensions
  
  Spree::Variant.class_eval do
    validates :sku, uniqueness: true
  end
end
```

### Important Notes

#### 1. **You ALWAYS need to_prepare in development**

```ruby
# ❌ This will break in development
Spree::User.prepend MyDecorator

# ✅ This works in both development and production
Rails.application.config.to_prepare do
  Spree::User.prepend MyDecorator
end
```

#### 2. **The decoration method (prepend/include/class_eval) doesn't affect to_prepare**

`to_prepare` is about WHEN your code runs.  
`prepend/include/class_eval` is about HOW you modify the class.

They're independent concerns:

```ruby
Rails.application.config.to_prepare do
  # WHEN: After every reload
  
  Spree::User.prepend UserDecorator
  # HOW: Using prepend to modify the class
end
```

#### 3. **All three can be mixed**

```ruby
Rails.application.config.to_prepare do
  # Use different patterns for different needs
  Spree::User.prepend Spree::UserDecorator        # For wrapping methods
  Spree::User.include Spree::UserHelpers          # For adding helpers
  
  Spree::Product.class_eval do                    # For simple additions
    validates :name, length: { minimum: 3 }
  end
  
  Spree::Order.prepend Spree::OrderDecorator      # For complex overrides
end
```

#### 4. **class_eval can be inline or in a file**

```ruby
# Option A: Inline class_eval
Rails.application.config.to_prepare do
  Spree::User.class_eval do
    def custom_method
      "inline"
    end
  end
end

# Option B: Load decorator file
Rails.application.config.to_prepare do
  require_dependency 'spree/user_decorator'
end

# app/models/spree/user_decorator.rb
Spree::User.class_eval do
  def custom_method
    "from file"
  end
end
```

### Real-World Example: Using All Three Together

```ruby
# config/initializers/spree.rb
Rails.application.config.to_prepare do
  # prepend: Wrap existing confirmation behavior
  Spree::User.prepend Spree::UserConfirmableDecorator
  
  # include: Add utility methods
  Spree::User.include Spree::UserHelpers
  
  # class_eval: Add simple validations and scopes
  Spree::User.class_eval do
    validates :phone, presence: true, if: :confirmed?
    scope :premium, -> { where(premium: true) }
  end
  
  # Another model with different pattern
  Spree::Order.class_eval do
    after_create :send_order_notification
    
    private
    
    def send_order_notification
      OrderMailer.created(self).deliver_later
    end
  end
end
```

### Summary: to_prepare vs Decoration Methods

| Aspect | to_prepare | prepend/include/class_eval |
|--------|-----------|---------------------------|
| **Purpose** | WHEN code runs | HOW you modify class |
| **Solves** | Code reloading issues | Method modification approach |
| **Required?** | YES (for decorators) | Choose based on need |
| **Independent?** | Works with all three | Works inside to_prepare |

### Final Answer

**YES, you can use `to_prepare` with `class_eval`, `include`, and `prepend` interchangeably!**

- `to_prepare` wraps ALL of them
- It ensures your modifications survive code reloads
- The choice of `prepend`/`include`/`class_eval` depends on WHAT you're modifying, not whether you use `to_prepare`

**Best practice:**

```ruby
Rails.application.config.to_prepare do
  # Always wrap your decorators here
  # Then choose prepend/include/class_eval based on your needs
  
  # prepend: When wrapping/decorating existing methods
  Spree::User.prepend Spree::UserDecorator
  
  # class_eval: When adding simple things
  Spree::Product.class_eval do
    validates :name, presence: true
  end
  
  # include: When adding utility methods only
  Spree::Order.include Spree::OrderHelpers
end
```

---

## 8. Can class_eval Work Without to_prepare?

**Question:** If adding only new methods, validations, scopes (no overrides), can we skip `to_prepare`?

**Answer:** **NO - Always use `to_prepare`, even for simple additions.**

### Why to_prepare is Always Required

```ruby
# ❌ WITHOUT to_prepare
Spree::User.class_eval do
  validates :phone, presence: true
  scope :premium, -> { where(premium: true) }
  def full_name; "#{firstname} #{lastname}"; end
end

# Development:
# Request 1: works ✅
# [code reload happens]
# Request 2: NoMethodError, validation missing ❌
```

**Problem:** Rails reloads `Spree::User` in development, but your `class_eval` ran only once. Your changes are lost.

```ruby
# ✅ WITH to_prepare
Rails.application.config.to_prepare do
  Spree::User.class_eval do
    validates :phone, presence: true
    scope :premium, -> { where(premium: true) }
    def full_name; "#{firstname} #{lastname}"; end
  end
end

# Development:
# Request 1: works ✅
# [code reload happens - to_prepare runs again]
# Request 2: still works ✅
```

### Quick Comparison

| Without to_prepare | With to_prepare |
|-------------------|-----------------|
| ✅ Works in production | ✅ Works in production |
| ❌ Breaks in development | ✅ Works in development |
| ❌ Bad practice | ✅ Best practice |

**Rule:** Always wrap decorators in `to_prepare`, no exceptions.

---

## 9. Auto-Loading All Decorators

Instead of manually loading each decorator, add this to `config/application.rb` to **automatically load all decorator files**:

```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    # ... other config
    
    # Auto-load all decorators
    config.to_prepare do
      Dir.glob(Rails.root.join('app/**/*_decorator*.rb')).each do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end
  end
end
```

**What this does:**
- Finds all files matching `*_decorator*.rb` pattern in `app/` directory
- **Production** (`cache_classes = true`): Uses `require` (load once)
- **Development** (`cache_classes = false`): Uses `load` (reload every time)
- Automatically loads all your decorators without manual configuration

**File structure it supports:**

```
app/
├── models/
│   ├── spree/
│   │   ├── user_decorator.rb          ✅ Loaded
│   │   └── product_decorator.rb       ✅ Loaded
│   └── concerns/
│       └── order_decorator.rb          ✅ Loaded
└── controllers/
    └── api/
        └── auth_controller_decorator.rb ✅ Loaded
```

**Benefits:**
- ✅ No need to manually add each decorator to initializers
- ✅ Consistent loading behavior
- ✅ Works for models, controllers, helpers, etc.
- ✅ Automatically picks up new decorators

**Now you can create decorators and they're auto-loaded:**

```ruby
# app/models/spree/user_decorator.rb
Spree::User.class_eval do
  validates :phone, presence: true
  scope :premium, -> { where(premium: true) }
end

# app/models/spree/product_decorator.rb
module Spree
  module ProductDecorator
    def discounted?
      price < compare_at_price
    end
  end
end
Spree::Product.prepend Spree::ProductDecorator

# No need to manually load them - auto-loaded! ✅
```