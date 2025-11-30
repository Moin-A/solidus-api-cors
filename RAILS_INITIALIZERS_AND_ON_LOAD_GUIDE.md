# Rails Initializers and ActiveSupport.on_load Guide

A comprehensive guide to understanding and using Rails initializers and the `on_load` pattern.

---

## Table of Contents

1. [What is an Initializer?](#what-is-an-initializer)
2. [The Problem: Lazy Loading](#the-problem-lazy-loading)
3. [What is ActiveSupport.on_load?](#what-is-activesupporton_load)
4. [Basic Example: How on_load Works](#basic-example-how-on_load-works)
5. [Creating Your Own Library with on_load](#creating-your-own-library-with-on_load)
6. [Real-World Examples](#real-world-examples)
7. [When to Use on_load vs after_initialize](#when-to-use-on_load-vs-after_initialize)
8. [Common Rails Hooks](#common-rails-hooks)

---

## What is an Initializer?

An **initializer** is a Ruby file in `config/initializers/` that runs when Rails starts up. It's used to configure your application.

```ruby
# config/initializers/my_config.rb

# This runs ONCE when Rails boots
puts "Rails is starting up!"

# Set a configuration
Rails.application.config.my_setting = "hello"
```

**Key Points:**
- Runs **once** at startup (in production)
- Runs **before** your app code loads
- Perfect for configuration and setup

---

## The Problem: Lazy Loading

Rails uses **lazy loading** - classes aren't loaded until they're actually used. This creates a problem:

```ruby
# config/initializers/broken_example.rb

# ❌ THIS WILL CRASH!
ActiveRecord::Base.class_eval do
  def my_method
    "Hello"
  end
end

# Error: NameError: uninitialized constant ActiveRecord::Base
# Why? Because ActiveRecord::Base hasn't been loaded yet!
```

**The Problem:**
- Initializers run **before** most classes are loaded
- If you try to modify a class that doesn't exist yet → **NameError**

**The Solution:** Use `on_load` to wait for the class to load first!

---

## What is ActiveSupport.on_load?

`ActiveSupport.on_load` is a **callback mechanism** that runs code **when a specific class loads**.

### Basic Syntax

```ruby
ActiveSupport.on_load(:class_name) do
  # This code runs WHEN class_name is loaded
  # By this time, the class definitely exists!
end
```

### How It Works

```ruby
# Step 1: You register a callback
ActiveSupport.on_load(:active_record) do
  puts "ActiveRecord just loaded!"
end

# Step 2: Later, when Rails loads ActiveRecord::Base...
# Step 3: Rails triggers the :active_record hook
# Step 4: Your callback runs!
```

---

## Basic Example: How on_load Works

### Example 1: Adding a Method to All Models

```ruby
# config/initializers/add_method_to_models.rb

# ❌ WRONG - This crashes!
# ActiveRecord::Base.class_eval do
#   def hello
#     "Hello from all models!"
#   end
# end

# ✅ CORRECT - Wait for ActiveRecord to load
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.class_eval do
    def hello
      "Hello from all models!"
    end
  end
end
```

**Now you can use it:**
```ruby
# In your app
user = User.first
user.hello  # => "Hello from all models!"

product = Product.first
product.hello  # => "Hello from all models!"
```

### Example 2: Modifying a Controller

```ruby
# config/initializers/add_controller_method.rb

ActiveSupport.on_load(:action_controller) do
  ActionController::Base.class_eval do
    def current_store
      @current_store ||= Store.find_by(domain: request.host)
    end
  end
end
```

**Now all controllers have this method:**
```ruby
# In any controller
class ProductsController < ApplicationController
  def index
    store = current_store  # Available everywhere!
  end
end
```

---

## Creating Your Own Library with on_load

Let's create a simple library that uses `on_load` so other developers can hook into it.

### Step 1: Create the Library

```ruby
# lib/my_library.rb

module MyLibrary
  # This is where we store callbacks
  @callbacks = {}
  
  # Method to register callbacks
  def self.on_load(name, &block)
    @callbacks[name] ||= []
    @callbacks[name] << block
  end
  
  # Method to trigger callbacks
  def self.run_callbacks(name)
    return unless @callbacks[name]
    @callbacks[name].each(&:call)
  end
  
  # Our main class
  class Base
    # When this class loads, trigger the hook
    def self.inherited(subclass)
      MyLibrary.run_callbacks(:my_library_base)
      super
    end
  end
end
```

### Step 2: Use the Library in Your App

```ruby
# config/initializers/my_library_setup.rb

# Register a callback that runs when MyLibrary::Base loads
MyLibrary.on_load(:my_library_base) do
  puts "MyLibrary::Base just loaded!"
  
  # Now we can safely modify it
  MyLibrary::Base.class_eval do
    def custom_method
      "This method was added via on_load!"
    end
  end
end
```

### Step 3: Load the Class (Triggers the Hook)

```ruby
# app/models/my_model.rb

class MyModel < MyLibrary::Base
  # When this class is defined, it inherits from MyLibrary::Base
  # That triggers MyLibrary::Base.inherited
  # Which calls MyLibrary.run_callbacks(:my_library_base)
  # Which runs your callback from the initializer!
end
```

### Complete Working Example

```ruby
# lib/payment_processor.rb

module PaymentProcessor
  @callbacks = {}
  
  def self.on_load(name, &block)
    @callbacks[name] ||= []
    @callbacks[name] << block
  end
  
  def self.run_callbacks(name)
    @callbacks[name]&.each(&:call)
  end
  
  class Gateway
    def self.inherited(subclass)
      PaymentProcessor.run_callbacks(:gateway)
      super
    end
    
    def process(amount)
      "Processing $#{amount}"
    end
  end
end

# config/initializers/payment_processor_setup.rb

PaymentProcessor.on_load(:gateway) do
  puts "PaymentProcessor::Gateway loaded!"
  
  PaymentProcessor::Gateway.class_eval do
    def validate_card
      "Card validated!"
    end
  end
end

# app/models/stripe_gateway.rb

class StripeGateway < PaymentProcessor::Gateway
  # When this loads, it triggers the on_load callback
  # So validate_card method is automatically added!
end

# Usage:
gateway = StripeGateway.new
gateway.process(100)      # => "Processing $100"
gateway.validate_card     # => "Card validated!" (added via on_load!)
```

---

## Real-World Examples

### Example 1: Active Storage (What We're Doing)

```ruby
# config/initializers/active_storage_cloudfront.rb

ActiveSupport.on_load(:active_storage_blob) do
  # Wait for ActiveStorage::Blob to load
  # By then, S3Service is guaranteed to exist
  require 'active_storage/service/s3_service'
  
  ActiveStorage::Service::S3Service.class_eval do
    def url(key, expires_in:, filename:, disposition:, content_type:)
      # Replace S3 URL with CloudFront URL
      "#{ENV['CLOUDFRONT_URL']}/#{key}"
    end
  end
end
```

### Example 2: Adding Logging to All Models

```ruby
# config/initializers/add_model_logging.rb

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.class_eval do
    after_create :log_creation
    
    private
    
    def log_creation
      Rails.logger.info "Created #{self.class.name} ##{id}"
    end
  end
end
```

### Example 3: Adding a Helper to All Controllers

```ruby
# config/initializers/add_controller_helper.rb

ActiveSupport.on_load(:action_controller) do
  ActionController::Base.class_eval do
    helper_method :current_tenant
    
    def current_tenant
      @current_tenant ||= Tenant.find_by(subdomain: request.subdomain)
    end
  end
end
```

---

## When to Use on_load vs after_initialize vs to_prepare

### Use `on_load` When:
- ✅ Modifying **Rails framework classes** (ActiveRecord, ActionController, etc.)
- ✅ Modifying **gem classes** that use lazy loading
- ✅ You need to wait for a specific class to load

```ruby
# Modifying Rails framework
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.class_eval do
    # your code
  end
end
```

### Use `to_prepare` When:
- ✅ **Monkey patching** any class or module (Rails or your own)
- ✅ Modifying classes that might get reloaded in development
- ✅ Adding methods/callbacks that need to survive code reloads

```ruby
# Monkey patching (works in development AND production)
Rails.application.config.to_prepare do
  Spree::ActiveStorageAdapter.module_eval do
    def attachment_url
      # This survives code reloads in development!
    end
  end
end
```

**Why `to_prepare` for monkey patching?**
- In **development**, Rails reloads code on every request
- Without `to_prepare`, your patch gets lost after the first reload
- `to_prepare` runs **after every reload**, ensuring your patch survives
- In **production**, `to_prepare` only runs once (no performance penalty)

### Use `after_initialize` When:
- ✅ **One-time setup** that doesn't modify classes
- ✅ Configuration that doesn't need to survive reloads
- ✅ Code that should only run once (not on every reload)

```ruby
# One-time setup (not monkey patching)
Rails.application.config.after_initialize do
  # Set up external services, configure libraries, etc.
  PaymentGateway.configure(api_key: ENV['API_KEY'])
end
```

### Comparison

| Scenario | Use This | Why? |
|----------|----------|------|
| Modify ActiveRecord::Base | `on_load(:active_record)` | Wait for class to load |
| Modify ActionController::Base | `on_load(:action_controller)` | Wait for class to load |
| Modify ActiveStorage classes | `on_load(:active_storage_blob)` | Wait for class to load |
| **Monkey patch your own models** | `to_prepare` | Survives code reloads |
| **Monkey patch your own modules** | `to_prepare` | Survives code reloads |
| **Monkey patch gem classes** | `to_prepare` | Survives code reloads |
| One-time configuration | `after_initialize` | Only needs to run once |

### module_eval vs class_eval

**When modifying modules:**
```ruby
# ✅ CORRECT - Use module_eval for modules
Spree::ActiveStorageAdapter.module_eval do
  def attachment_url
    # ...
  end
end

# ⚠️ WORKS BUT LESS CLEAR - class_eval also works on modules
Spree::ActiveStorageAdapter.class_eval do
  def attachment_url
    # ...
  end
end
```

**When modifying classes:**
```ruby
# ✅ CORRECT - Use class_eval for classes
User.class_eval do
  def full_name
    "#{first_name} #{last_name}"
  end
end

# ⚠️ WORKS BUT LESS CLEAR - module_eval also works on classes
User.module_eval do
  def full_name
    "#{first_name} #{last_name}"
  end
end
```

**Rule of thumb:**
- **Modules** → Use `module_eval` (semantically correct)
- **Classes** → Use `class_eval` (semantically correct)
- Both work on both, but using the right one makes code clearer!

---

## Common Rails Hooks

Rails provides these built-in hooks you can use:

| Hook Name | When It Triggers | Use Case |
|-----------|------------------|----------|
| `:active_record` | When `ActiveRecord::Base` loads | Modify all models |
| `:action_controller` | When `ActionController::Base` loads | Modify all controllers |
| `:action_view` | When `ActionView::Base` loads | Modify all views |
| `:action_mailer` | When `ActionMailer::Base` loads | Modify all mailers |
| `:active_storage_blob` | When `ActiveStorage::Blob` loads | Modify Active Storage |
| `:active_job` | When `ActiveJob::Base` loads | Modify all jobs |

### Example: Using Multiple Hooks

```ruby
# config/initializers/add_helpers_everywhere.rb

# Add method to all models
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.class_eval do
    def formatted_created_at
      created_at.strftime("%B %d, %Y")
    end
  end
end

# Add method to all controllers
ActiveSupport.on_load(:action_controller) do
  ActionController::Base.class_eval do
    def current_user
      @current_user ||= User.find(session[:user_id])
    end
  end
end

# Add method to all mailers
ActiveSupport.on_load(:action_mailer) do
  ActionMailer::Base.class_eval do
    def default_from
      "noreply@example.com"
    end
  end
end
```

---

## Quick Reference

### Pattern: Modify a Rails Framework Class

```ruby
ActiveSupport.on_load(:hook_name) do
  ClassName.class_eval do
    # Your modifications
  end
end
```

### Pattern: Modify Your Own Class

```ruby
Rails.application.config.after_initialize do
  MyClass.class_eval do
    # Your modifications
  end
end
```

### Pattern: Create a Library with on_load

```ruby
# In your library
module MyLibrary
  @callbacks = {}
  
  def self.on_load(name, &block)
    @callbacks[name] ||= []
    @callbacks[name] << block
  end
  
  def self.run_callbacks(name)
    @callbacks[name]&.each(&:call)
  end
  
  class Base
    def self.inherited(subclass)
      MyLibrary.run_callbacks(:my_library_base)
      super
    end
  end
end
```

---

## Summary

**Key Takeaways:**

1. **Initializers run before classes load** - This is why we need `on_load`
2. **`on_load` waits for a class to load** - Then runs your code
3. **Use `on_load` for Rails/gem classes** - They use lazy loading
4. **Use `after_initialize` for your own classes** - They're loaded by then
5. **You can create your own `on_load` system** - For your libraries

**The Pattern:**
```
Register callback → Class loads → Hook triggers → Your code runs → Class is modified
```

This pattern is powerful and reusable - use it whenever you need to modify classes that might not be loaded yet!

---

**Created:** January 2025  
**Topic:** Rails Initializers and ActiveSupport.on_load  
**Related Files:** `config/initializers/active_storage_cloudfront.rb`, `RAILS_APPLICATION_CONFIG_EXPLAINED.md`



---
why would we need a code to rerun on every request response cysle

Great question! It seems counterintuitive, but there's a very important reason related to how Rails development mode works.

The Class Reloading Problem
In development mode, Rails reloads your application code on every request so you can see changes without restarting the server. This creates a problem:

When classes are reloaded, any modifications you made to them are lost.

Examples Where You Need to_prepare
1. Adding Methods to Rails Classes
ruby
# This WON'T work correctly in development:
config.after_initialize do
  ApplicationController.class_eval do
    def current_site
      @current_site ||= Site.find_by(domain: request.host)
    end
  end
end
Problem: After the first request, ApplicationController gets reloaded (wiped clean), and your current_site method disappears!

ruby
# This WILL work in development:
config.to_prepare do
  ApplicationController.class_eval do
    def current_site
      @current_site ||= Site.find_by(domain: request.host)
    end
  end
end
Solution: By using to_prepare, your method gets re-added after each reload.

2. Monkey Patching Gems
ruby
config.to_prepare do
  Devise::SessionsController.class_eval do
    # Your custom behavior
    def after_sign_in_path_for(resource)
      custom_dashboard_path
    end
  end
end
Without to_prepare, your patch would disappear after the first request in development.

3. Registering Observers or Callbacks
ruby
config.to_prepare do
  ActiveSupport::Notifications.subscribe('user.created') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    UserMailer.welcome_email(event.payload[:user]).deliver_later
  end
end
In Production
In production, class reloading is disabled (for performance), so to_prepare only runs once—just like after_initialize. You get the best of both worlds:

Development: Works correctly with code reloading
Production: No performance penalty
TL;DR
You don't need code to rerun for the request/response cycle itself—you need it to rerun because Rails reloads your classes in development, and to_prepare ensures your modifications survive those reloads.



How can I help you today?








