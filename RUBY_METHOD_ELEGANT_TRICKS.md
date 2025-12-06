# Ruby Method Elegant Tricks

A collection of elegant Ruby patterns and techniques for writing clean, maintainable code.

---

## Table of Contents
1. [Class Instance Variables with `super` for Inheritable Registries](#class-instance-variables-with-super-for-inheritable-registries)
2. [The `ensure` Block Pattern](#the-ensure-block-pattern)
3. [Dynamic Method Definition with `define_singleton_method`](#dynamic-method-definition-with-define_singleton_method)
4. [Module Extension Pattern (`self.extended`)](#module-extension-pattern-selfextended)
5. [ActiveRecord Joins: Using Table Names in Queries](#activerecord-joins-using-table-names-in-queries)
6. [Prepending Modules: Self-Registering Pattern](#prepending-modules-self-registering-pattern)

---

## Class Instance Variables with `super` # Registry Pattern Examples in Ruby on Rails

The **Registry Pattern** is a design pattern where you maintain a list of registered items (methods, classes, callbacks, etc.) that can be discovered and used dynamically at runtime.

## Core Concept

```ruby
class MyModel < ApplicationRecord
  # Registry to store registered items
  cattr_accessor :registered_items do
    []
  end
  
  # Method to register new items
  def self.register_item(name, &block)
    # Define the method
    singleton_class.send(:define_method, name.to_sym, &block)
    # Add to registry
    registered_items << name.to_sym
  end
end
```

## Example 1: Auto-Generate Search APIs

**Use Case**: Build a flexible REST API where search capabilities are automatically exposed based on registered scopes.

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  cattr_accessor :search_scopes do
    []
  end
  
  def self.add_search_scope(name, &block)
    singleton_class.send(:define_method, name.to_sym, &block)
    search_scopes << name.to_sym
  end
  
  # Register various search scopes
  add_search_scope :by_category do |category|
    where(category: category)
  end
  
  add_search_scope :price_range do |min, max|
    where(price: min..max)
  end
  
  add_search_scope :in_stock do
    where("inventory > ?", 0)
  end
  
  add_search_scope :by_name do |query|
    where("name ILIKE ?", "%#{query}%")
  end
end

# app/controllers/api/v1/products_controller.rb
class Api::V1::ProductsController < ApplicationController
  def index
    @products = Product.all
    
    # Automatically apply any registered search scope from query params
    Product.search_scopes.each do |scope_name|
      if params[scope_name].present?
        args = parse_scope_arguments(params[scope_name])
        @products = @products.public_send(scope_name, *args)
      end
    end
    
    render json: @products
  end
  
  # Auto-generate API documentation
  def available_filters
    filters = Product.search_scopes.map do |scope_name|
      {
        name: scope_name,
        description: "Filter products by #{scope_name.to_s.humanize}",
        example: "/api/v1/products?#{scope_name}=value"
      }
    end
    
    render json: { available_filters: filters }
  end
  
  private
  
  def parse_scope_arguments(value)
    # Handle comma-separated values for scopes with multiple args
    value.to_s.include?(',') ? value.split(',') : [value]
  end
end

# Usage Examples:
# GET /api/v1/products?by_category=electronics
# GET /api/v1/products?price_range=10,50
# GET /api/v1/products?in_stock=true&by_name=laptop
# GET /api/v1/products/available_filters  # See all available search options
```

**Benefits**:
- ✅ Add new search capability = automatically available in API
- ✅ No need to update controller for each new scope
- ✅ Auto-generated documentation knows all available filters
- ✅ Consistent API structure

---

## Example 2: Query Builder DSL with Chainable Filters

**Use Case**: Create a fluent interface for building complex queries with validation.

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  cattr_accessor :query_filters do
    {}
  end
  
  def self.register_filter(name, validator: nil, &block)
    # Store filter metadata
    query_filters[name.to_sym] = {
      block: block,
      validator: validator
    }
    
    # Define the scope
    singleton_class.send(:define_method, name.to_sym, &block)
  end
  
  # Register filters with validators
  register_filter :by_price_range, validator: ->(min, max) {
    min.to_f >= 0 && max.to_f >= min.to_f
  } do |min, max|
    where(price: min.to_f..max.to_f)
  end
  
  register_filter :by_status, validator: ->(status) {
    %w[active inactive discontinued].include?(status)
  } do |status|
    where(status: status)
  end
  
  register_filter :by_brand do |brand|
    where(brand: brand)
  end
  
  register_filter :in_stock_only do
    where("inventory_count > ?", 0)
  end
  
  register_filter :recently_added do |days = 7|
    where("created_at >= ?", days.to_i.days.ago)
  end
end

# app/services/product_query_builder.rb
class ProductQueryBuilder
  attr_reader :relation, :applied_filters, :errors
  
  def initialize(base_relation = Product.all)
    @relation = base_relation
    @applied_filters = []
    @errors = []
  end
  
  # Dynamically create methods for each registered filter
  Product.query_filters.each do |filter_name, metadata|
    define_method(filter_name) do |*args|
      apply_filter(filter_name, args, metadata)
      self # Return self for chaining
    end
  end
  
  def apply_filters(filter_hash)
    filter_hash.each do |filter_name, args|
      filter_name = filter_name.to_sym
      
      if Product.query_filters.key?(filter_name)
        metadata = Product.query_filters[filter_name]
        args = Array(args)
        apply_filter(filter_name, args, metadata)
      else
        @errors << "Unknown filter: #{filter_name}"
      end
    end
    self
  end
  
  def valid?
    @errors.empty?
  end
  
  def results
    valid? ? @relation : Product.none
  end
  
  def to_sql
    @relation.to_sql
  end
  
  private
  
  def apply_filter(filter_name, args, metadata)
    validator = metadata[:validator]
    
    # Validate if validator exists
    if validator && !validator.call(*args)
      @errors << "Invalid arguments for #{filter_name}: #{args.inspect}"
      return
    end
    
    # Apply the filter
    @relation = @relation.public_send(filter_name, *args)
    @applied_filters << { name: filter_name, args: args }
  end
end

# Usage Examples:

# Example 1: Fluent/chainable interface
search = ProductQueryBuilder.new
results = search
  .by_status('active')
  .by_price_range(10, 100)
  .in_stock_only
  .recently_added(30)
  .results

# Example 2: Build from hash (useful for saved searches)
saved_search = {
  by_status: 'active',
  by_price_range: [50, 200],
  by_brand: 'Sony'
}

search = ProductQueryBuilder.new.apply_filters(saved_search)

if search.valid?
  products = search.results
else
  puts "Errors: #{search.errors.join(', ')}"
end

# Example 3: Inspect what filters were applied
search = ProductQueryBuilder.new
  .by_status('active')
  .by_brand('Apple')

puts search.applied_filters
# => [
#      { name: :by_status, args: ['active'] },
#      { name: :by_brand, args: ['Apple'] }
#    ]

# Example 4: Get SQL for debugging
search = ProductQueryBuilder.new
  .by_price_range(100, 500)
  .in_stock_only

puts search.to_sql
# => SELECT "products".* FROM "products" 
#    WHERE "products"."price" BETWEEN 100 AND 500 
#    AND (inventory_count > 0)
```

**Benefits**:
- ✅ Chainable, readable query building
- ✅ Built-in validation for filter arguments
- ✅ Track which filters were applied (useful for debugging/analytics)
- ✅ Easy to save and restore search configurations
- ✅ Type-safe: only registered filters can be used
- ✅ Add new filter = automatically available in query builder

---

## Example 3: Auto-Generate Admin UI Forms

**Use Case**: Create admin search forms that automatically update when new scopes are added.

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  cattr_accessor :search_scopes_metadata do
    {}
  end
  
  def self.add_search_scope(name, label: nil, input_type: :text, &block)
    # Store metadata for UI generation
    search_scopes_metadata[name.to_sym] = {
      label: label || name.to_s.humanize,
      input_type: input_type
    }
    
    # Define the scope
    singleton_class.send(:define_method, name.to_sym, &block)
  end
  
  add_search_scope :by_name, 
    label: "Product Name",
    input_type: :text do |query|
    where("name ILIKE ?", "%#{query}%")
  end
  
  add_search_scope :by_category,
    label: "Category",
    input_type: :select do |category|
    where(category: category)
  end
  
  add_search_scope :price_min,
    label: "Minimum Price",
    input_type: :number do |price|
    where("price >= ?", price)
  end
  
  add_search_scope :in_stock,
    label: "In Stock Only",
    input_type: :checkbox do
    where("inventory > 0")
  end
end

# app/helpers/admin/search_helper.rb
module Admin::SearchHelper
  def render_search_form(model_class)
    content_tag :div, class: 'search-form' do
      form_with url: admin_products_path, method: :get do |f|
        model_class.search_scopes_metadata.map do |scope_name, metadata|
          render_search_field(f, scope_name, metadata)
        end.join.html_safe
      end
    end
  end
  
  def render_search_field(form, scope_name, metadata)
    content_tag :div, class: 'form-group' do
      label = form.label scope_name, metadata[:label]
      
      input = case metadata[:input_type]
      when :text
        form.text_field scope_name, class: 'form-control'
      when :number
        form.number_field scope_name, class: 'form-control'
      when :select
        options = get_select_options(scope_name)
        form.select scope_name, options, { include_blank: true }, class: 'form-control'
      when :checkbox
        form.check_box scope_name
      end
      
      label + input
    end
  end
end

# app/views/admin/products/index.html.erb
<h1>Search Products</h1>

<%= render_search_form(Product) %>

<div id="results">
  <%= render @products %>
</div>

<!-- Generated HTML will look like:
<div class="search-form">
  <form action="/admin/products" method="get">
    <div class="form-group">
      <label>Product Name</label>
      <input type="text" name="by_name" class="form-control">
    </div>
    <div class="form-group">
      <label>Category</label>
      <select name="by_category" class="form-control">...</select>
    </div>
    <div class="form-group">
      <label>Minimum Price</label>
      <input type="number" name="price_min" class="form-control">
    </div>
    <div class="form-group">
      <label>In Stock Only</label>
      <input type="checkbox" name="in_stock">
    </div>
  </form>
</div>
-->
```

**Benefits**:
- ✅ Add new scope = form automatically updates
- ✅ Consistent UI across different models
- ✅ No need to manually update views
- ✅ Metadata-driven UI generation

---

## Key Takeaways

The Registry Pattern is powerful when you need:

1. **Dynamic Discovery**: "What capabilities are available?"
2. **Metaprogramming**: Auto-generate UIs, APIs, documentation
3. **Extensibility**: Plugins can add features without modifying core code
4. **Consistency**: Enforce conventions across your codebase
5. **Security**: Whitelist safe operations

**When NOT to use it**:
- Simple CRUD apps with static requirements
- When you don't need dynamic discovery
- When explicit is better than magic (team preference)

The pattern trades some explicitness for flexibility and maintainability in systems that need to be highly extensible.for Inheritable Registries

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

## ActiveRecord Joins: Using Table Names in Queries

### Pattern Overview

When using `joins` in ActiveRecord, use the actual database table name (not association names) in `where` clauses with parameterized queries.

### Key Concept

- **Association names** (`:master`, `:prices`) are for Rails associations
- **Table names** (`spree_prices`, `spree_variants`) are for SQL queries
- In `where` clauses, reference the actual table name from the database

### Example

```ruby
# Joins use association names
@products = @products.joins(master: :prices)

# But where clauses use actual table names
@products = @products.where("spree_prices.amount >= ?", min_price)
```

### Alternative Syntax

You can also use hash syntax, which Rails converts automatically:

```ruby
# Hash syntax (Rails converts to table name)
@products.joins(:taxons).where(spree_taxons: { id: category_id })

# String with parameterized query
@products.joins(master: :prices).where("spree_prices.amount >= ?", min_price)
```

### Real-World Example

```ruby
# From Solidus codebase
Spree::User.joins(:spree_roles).where(spree_roles: { name: 'customer' }).first

# Nested joins
@products.joins(master: :prices).where("spree_prices.amount >= ?", min_price)
```

### Key Points

- Use association names in `joins()` for Rails to build SQL
- Use actual table names in `where()` clauses (often prefixed like `spree_`)
- Parameterized queries (`?`) prevent SQL injection
- Hash syntax automatically converts to table names

---

## Prepending Modules: Self-Registering Pattern

### Pattern Overview

A module that prepends itself to a class when loaded. Commonly used in Rails for extending models without modifying the original class.

### Steps to Create a Prepended Module

1. **Create a module**
2. **Define `self.prepended(base)` block** - Runs when module is prepended
3. **Add instance/class methods** - Methods that will be added to the target class
4. **At the end, write `TargetClass.prepend self`** - Self-registration

### Example

```ruby
module ProductFeaturedSimilarProducts
  def self.prepended(base)
    base.scope :featured, -> { where(featured: true) }
  end

  def similar_products(limit = 3)
    taxons.map { |taxon| taxon.all_products_except(self.id) }
          .flatten.uniq.first(limit)
  end

  Spree::Product.prepend self  # ← Self-registration at the end
end
```

### Loading the Module

Two ways to load:

1. **Autoloading** (Rails default) - Loads when first referenced
   - Works, but can have timing issues in development
   - Less reliable for self-registering modules

2. **`require_dependency`** (Recommended) - Explicit loading
   ```ruby
   # In the target class file (e.g., product.rb)
   require_dependency 'overrides/product_featured_similar_products'
   ```
   - Loads immediately when class loads
   - Properly reloads in development
   - More reliable for self-registering modules

### Wrapping Methods with `super`

Prepend allows you to wrap existing methods by adding code before/after the original method:

```ruby
module ProductLogging
  def self.prepended(base)
    # Add new methods/scopes here
  end

  def save
    # BEFORE: Add logic before original
    Rails.logger.info "Saving product: #{name}"
    
    # Call original method
    result = super
    
    # AFTER: Add logic after original
    Rails.logger.info "Product saved: #{result}" if result
    
    result
  end
end

Spree::Product.prepend ProductLogging
```

**Why prepend works for wrapping:**
- Module comes FIRST in method lookup chain
- `super` reliably finds the original class method
- With `include`, `super` might not find the original method

**Method execution flow:**
```
1. ProductLogging#save (wrapper) ← Runs first
2. Calls super
3. Product#save (original) ← Runs second
4. Returns to wrapper
```

### The `::` Prefix

The `::` at the start of a constant means "start from root namespace":

```ruby
Spree::Product      # Relative lookup (might find local Product)
::Spree::Product    # Absolute lookup (always finds root Spree::Product)
```

**Why use `::`?**
- Prevents shadowing by local constants
- Guarantees you reference the correct class
- Best practice in nested modules

### Key Points

- `self.prepended(base)` runs automatically when module is prepended
- `self` at module level = the module itself
- `self` inside instance methods = the instance (after prepend)
- Use `require_dependency` for reliable loading in development
- Use `::` prefix for absolute namespace lookup
- Use `super` to call original method when wrapping

---

## ActiveRecord Inverse Associations (`inverse_of`)

### Pattern Overview

The `inverse_of` option tells Rails about the other side of a bidirectional association. **The value must EXACTLY match the association name on the other model**, not the table name or class name.

### The Golden Rule

**`inverse_of` is always the name you reference the association with, not the class or table name.**

If you use a custom association name (different from the default), `inverse_of` must use that custom name.

### Common Mistake

```ruby
# ❌ WRONG: Using default name when custom name exists
class Rating < ApplicationRecord
  belongs_to :user, inverse_of: :ratings  # ❌ User doesn't have :ratings
end

class User < ApplicationRecord
  has_many :product_ratings, class_name: "Rating"  # Custom name!
end

# Error: Could not find the inverse association for user (:ratings in User)
```

### Correct Pattern

```ruby
# ✅ CORRECT: Match the ACTUAL association name
class Rating < ApplicationRecord
  belongs_to :user, inverse_of: :product_ratings  # ✅ Matches has_many name
end

class User < ApplicationRecord
  has_many :product_ratings, class_name: "Rating", inverse_of: :user
end
```

### Why It Matters

Rails uses inverse associations to:
- **Avoid duplicate queries**: Reuse already-loaded objects
- **Maintain consistency**: Both sides of association point to same object in memory
- **Improve performance**: Reduce database round-trips

### Examples

**Example 1: Standard naming (no inverse_of needed)**
```ruby
class User < ApplicationRecord
  has_many :ratings  # Standard name
end

class Rating < ApplicationRecord
  belongs_to :user  # Rails auto-detects inverse
end
```

**Example 2: Custom naming (inverse_of required)**
```ruby
class User < ApplicationRecord
  has_many :product_ratings, class_name: "Rating", inverse_of: :user
end

class Rating < ApplicationRecord
  belongs_to :user, inverse_of: :product_ratings  # Must match :product_ratings
end
```

**Example 3: Through associations**
```ruby
class Product < ApplicationRecord
  has_many :classifications, inverse_of: :product
  has_many :taxons, through: :classifications
end

class Classification < ApplicationRecord
  belongs_to :product, inverse_of: :classifications  # Matches has_many name
  belongs_to :taxon, inverse_of: :classifications
end

class Taxon < ApplicationRecord
  has_many :classifications, inverse_of: :taxon
  has_many :products, through: :classifications
end
```

### Debugging Checklist

When you see: `Could not find the inverse association for X (:Y in Z)`

1. ✅ Check association name on other model - does `:Y` exist?
2. ✅ Is it a custom name? Use `inverse_of` with that exact name
3. ✅ Did you misspell singular/plural? (`rating` vs `ratings`)
4. ✅ Check class_name matches the correct model

### Key Points

- **Match the association name**, not the class or table name
- If `has_many :product_ratings`, use `inverse_of: :product_ratings`
- If `belongs_to :owner, class_name: "User"`, the User should have association with `inverse_of: :owner`
- Rails auto-detects inverse for standard naming (e.g., `User` ↔ `has_many :users`)
- Always specify `inverse_of` for custom association names

---

## Summary

These patterns are powerful tools for building flexible, maintainable Ruby code:

1. **Class Instance Variables + `super()`**: Create inheritable registries that collect data from ancestors
2. **`ensure` Blocks**: Guarantee cleanup code runs regardless of exceptions
3. **`define_singleton_method`**: Dynamically create class methods at runtime
4. **`self.extended`**: Initialize class-level state when modules are extended
5. **ActiveRecord Joins**: Use table names (not association names) in `where` clauses with parameterized queries
6. **Prepending Modules**: Self-registering pattern for extending classes with `self.prepended` and explicit loading
7. **Inverse Associations**: `inverse_of` must match the exact association name, especially with custom names

Each pattern solves specific problems elegantly and is commonly used in production Ruby frameworks like Rails and Solidus.

