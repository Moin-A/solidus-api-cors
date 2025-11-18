# Ruby Method Elegant Tricks

A collection of elegant Ruby patterns and techniques for writing clean, maintainable code.

---

## Table of Contents
1. [Class Instance Variables with `super` for Inheritable Registries](#class-instance-variables-with-super-for-inheritable-registries)
2. [The `ensure` Block Pattern](#the-ensure-block-pattern)
3. [Dynamic Method Definition with `define_singleton_method`](#dynamic-method-definition-with-define_singleton_method)
4. [Module Extension Pattern (`self.extended`)](#module-extension-pattern-selfextended)

---

## Class Instance Variables with `super` for Inheritable Registries

### Pattern Overview

This pattern allows you to create inheritable registries where each class maintains its own list of items while also collecting items from ancestor classes. It's commonly used in frameworks like Solidus for managing preferences, hooks, or other class-level configurations.

### How It Works

1. **Class Instance Variables**: Store data on the class itself (not instances) using `@variable_name`
2. **`super()` Traversal**: Use `super()` to call the parent class's method and collect ancestor data
3. **Dynamic Redefinition**: Use `define_singleton_method` to dynamically redefine methods as items are added

### Example: The Hookable Pattern

```ruby
module Hookable
  def self.extended(base)
    base.instance_variable_set(:@hooks, [])
  end

  def add_hook(name)
    hooks = (@hooks ||= [])
    hooks << name
  end

  def defined_hooks
    super() + (@hooks || [])
  end
end

# Usage
class BaseClass
  extend Hookable
  add_hook :before_save
  add_hook :after_save
end

class SubClass < BaseClass
  add_hook :before_validate
  add_hook :after_validate
end

BaseClass.defined_hooks
# => [:before_save, :after_save]

SubClass.defined_hooks
# => [:before_save, :after_save, :before_validate, :after_validate]
```

### Real-World Example: Solidus Preferences

From `lib/spree/preferences/preferable_class_methods.rb`:

```ruby
module Spree::Preferences::PreferableClassMethods
  def defined_preferences
    []
  end

  def preference(name, type, options = {})
    # Store preferences in a class instance variable
    singleton_preferences = (@defined_singleton_preferences ||= [])
    singleton_preferences << name.to_sym

    # Dynamically redefine the method to include this preference
    # super() collects preferences from ancestor classes
    define_singleton_method :defined_preferences do
      super() + singleton_preferences
    end

    # ... rest of preference definition logic
  end
end

# Usage
class Calculator
  extend Spree::Preferences::PreferableClassMethods
  preference :amount, :decimal, default: 0
end

class FlatRateCalculator < Calculator
  preference :currency, :string, default: 'USD'
end

Calculator.defined_preferences
# => [:amount]

FlatRateCalculator.defined_preferences
# => [:amount, :currency]  # Includes parent's preferences
```

### Key Points

- **Class Instance Variables**: `@hooks` or `@defined_singleton_preferences` are stored on the class, not instances
- **`super()` Returns Empty Array**: When there's no parent implementation, `super()` returns `[]`, so `super() + [items]` works correctly
- **Inheritance Chain**: `super()` traverses up the inheritance chain, collecting data from all ancestors
- **Per-Class State**: Each class has its own instance variable, so subclasses don't modify parent classes

### Why This Pattern?

1. **Inheritance-Friendly**: Subclasses automatically inherit parent configurations
2. **Non-Destructive**: Each class maintains its own list without modifying ancestors
3. **Dynamic**: Methods are redefined as items are added, ensuring the latest state
4. **Clean API**: Simple method calls like `MyClass.defined_hooks` return all relevant data

---

## The `ensure` Block Pattern

### Pattern Overview

The `ensure` block guarantees that cleanup code runs regardless of whether an exception occurs. This is essential for resource management, locking, and cleanup operations.

### Basic Syntax

```ruby
def risky_operation
  # Setup code
  acquire_resource
  perform_operation
rescue SpecificError => e
  # Handle specific errors
  handle_error(e)
  raise  # Re-raise if needed
ensure
  # This ALWAYS runs, even if an exception occurs
  release_resource
end
```

### Real-World Example: Payment Processing

```ruby
def capture_payment(payment)
  payment.start_processing!
  payment.source.authorize(amount: payment.amount)
  payment.complete!
  send_confirmation_email(payment)
rescue GatewayError => e
  payment.fail!
  Rails.logger.error("Payment #{payment.id} failed: #{e.message}")
  raise PaymentError, e.message
ensure
  # Always release lock, even if payment fails
  payment.release_lock if payment.locked?
  payment.clear_temp_data
end
```

### Common Use Cases

1. **File Operations**
```ruby
def read_file_safely(file_path)
  file = File.open(file_path, 'r')
  file.read
rescue IOError => e
  Rails.logger.error("Failed to read file: #{e.message}")
  raise
ensure
  file.close if file && !file.closed?
end
```

2. **Database Transactions**
```ruby
def process_order(order)
  ActiveRecord::Base.transaction do
    order.process!
    inventory.adjust!
    send_notifications
  end
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error("Order processing failed: #{e.message}")
  raise
ensure
  # Always clear cached data, even on failure
  Rails.cache.delete("order_#{order.id}")
  order.clear_temp_attributes
end
```

3. **API Calls with Timeouts**
```ruby
def fetch_external_data(url)
  response = nil
  timeout = Timeout.timeout(5) do
    response = Net::HTTP.get_response(URI(url))
  end
  JSON.parse(response.body)
rescue Timeout::Error => e
  Rails.logger.error("Request timed out: #{e.message}")
  raise
rescue JSON::ParserError => e
  Rails.logger.error("Invalid JSON response: #{e.message}")
  raise
ensure
  # Always log the request, even if it fails
  log_request(url, response&.code, Time.current)
end
```

### Key Points

- **Always Executes**: `ensure` blocks run even if:
  - An exception is raised
  - A `return` statement is executed
  - The method completes normally
- **Order Matters**: `ensure` runs after `rescue` blocks but before the method exits
- **Resource Cleanup**: Perfect for releasing locks, closing files, clearing caches
- **No Return Values**: Don't use `return` in `ensure` blocks (it can mask exceptions)

---

## Dynamic Method Definition with `define_singleton_method`

### Pattern Overview

`define_singleton_method` allows you to dynamically define class methods (singleton methods) at runtime. This is powerful for creating flexible APIs that adapt based on configuration or usage.

### Basic Syntax

```ruby
class MyClass
  define_singleton_method :dynamic_method do
    "This method was created dynamically!"
  end
end

MyClass.dynamic_method
# => "This method was created dynamically!"
```

### Real-World Example: Building Inheritable Registries

```ruby
module Configurable
  def config(name, value)
    # Store config in class instance variable
    configs = (@configs ||= [])
    configs << { name: name, value: value }

    # Redefine the method to include this config
    define_singleton_method :all_configs do
      super() + configs
    end
  end

  def all_configs
    []
  end
end

class Base
  extend Configurable
  config :api_key, 'secret123'
  config :timeout, 30
end

class Sub < Base
  config :retries, 3
end

Base.all_configs
# => [{ name: :api_key, value: 'secret123' }, { name: :timeout, value: 30 }]

Sub.all_configs
# => [{ name: :api_key, value: 'secret123' }, 
#     { name: :timeout, value: 30 },
#     { name: :retries, value: 3 }]
```

### Use Case: Preference System (Solidus)

```ruby
module PreferableClassMethods
  def defined_preferences
    []
  end

  def preference(name, type, options = {})
    singleton_preferences = (@defined_singleton_preferences ||= [])
    singleton_preferences << name.to_sym

    # Dynamically redefine to aggregate from ancestors
    define_singleton_method :defined_preferences do
      super() + singleton_preferences
    end
  end
end
```

### Key Points

- **Runtime Definition**: Methods are created when code executes, not at class definition time
- **Can Override**: Each call to `define_singleton_method` replaces the previous definition
- **Access to Closure**: The block has access to variables in the surrounding scope
- **Works with `super()`**: Can call parent implementations using `super()`

### When to Use

- Building DSLs (Domain-Specific Languages)
- Creating inheritable registries
- Dynamic API generation
- Framework internals that need to adapt based on usage

---

## Module Extension Pattern (`self.extended`)

### Pattern Overview

When a module is `extend`ed onto a class (not `include`d), the `self.extended(base)` callback is invoked. This allows you to set up class-level state when the module is extended.

### Basic Syntax

```ruby
module MyModule
  def self.extended(base)
    # This runs when MyModule is extended onto a class
    base.instance_variable_set(:@my_var, [])
  end

  def add_item(item)
    (@my_var ||= []) << item
  end

  def items
    @my_var || []
  end
end

class MyClass
  extend MyModule
  # @my_var is now initialized to []
end
```

### Comparison: `included` vs `extended`

```ruby
module Example
  # Runs when module is INCLUDED (instance methods)
  def self.included(base)
    base.class_eval do
      # Add instance methods here
    end
  end

  # Runs when module is EXTENDED (class methods)
  def self.extended(base)
    base.instance_variable_set(:@class_var, [])
  end
end

class MyClass
  include Example  # Triggers self.included
  extend Example    # Triggers self.extended
end
```

### Real-World Example: Hookable Module

```ruby
module Hookable
  def self.extended(base)
    # Initialize class instance variable when extended
    base.instance_variable_set(:@hooks, [])
  end

  def add_hook(name)
    hooks = (@hooks ||= [])
    hooks << name
  end

  def defined_hooks
    super() + (@hooks || [])
  end
end

class BaseClass
  extend Hookable
  add_hook :before_save
end

BaseClass.instance_variable_get(:@hooks)
# => [:before_save]
```

### In ActiveSupport::Concern

```ruby
module MyConcern
  extend ActiveSupport::Concern

  included do
    # Runs when module is INCLUDED
    # Adds instance methods, validations, etc.
    validates :name, presence: true
  end

  class_methods do
    # Adds class methods when module is INCLUDED
    def find_recent
      order(created_at: :desc).limit(5)
    end
  end

  # For extension, you'd still use self.extended
  def self.extended(base)
    base.instance_variable_set(:@extended_var, [])
  end
end
```

### Key Points

- **`extend` vs `include`**: 
  - `include` → adds instance methods → triggers `self.included`
  - `extend` → adds class methods → triggers `self.extended`
- **Class-Level Setup**: Perfect for initializing class instance variables
- **One-Time Setup**: Runs once when the module is extended, not per instance
- **Can Combine**: A module can have both `self.included` and `self.extended`

### When to Use

- Setting up class-level state (instance variables on the class)
- Initializing registries or collections at the class level
- Adding class methods that need initialization
- Building DSLs that work at the class level

---

## Summary

These patterns are powerful tools for building flexible, maintainable Ruby code:

1. **Class Instance Variables + `super()`**: Create inheritable registries that collect data from ancestors
2. **`ensure` Blocks**: Guarantee cleanup code runs regardless of exceptions
3. **`define_singleton_method`**: Dynamically create class methods at runtime
4. **`self.extended`**: Initialize class-level state when modules are extended

Each pattern solves specific problems elegantly and is commonly used in production Ruby frameworks like Rails and Solidus.

