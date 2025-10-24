# Preference System Q&A and Coding Exercises

## Questions & Answers from Learning Session

### Q1: Where is `assert_valid_keys` defined?

**Answer:**

`assert_valid_keys` is defined in **ActiveSupport** (part of Rails).

**Location:** `activesupport/lib/active_support/core_ext/hash/keys.rb`

**Source Code:**
```ruby
def assert_valid_keys(*valid_keys)
  valid_keys.flatten!
  each_key do |k|
    unless valid_keys.include?(k)
      raise ArgumentError.new("Unknown key: #{k.inspect}. Valid keys are: #{valid_keys.map(&:inspect).join(', ')}")
    end
  end
end
```

**What it does:**
- It's a **monkey patch** added to Ruby's `Hash` class
- Validates that all keys in a hash are in an allowed whitelist
- Raises `ArgumentError` if any key is not allowed
- Used to catch typos in hash options

**Example:**
```ruby
options = { default: 0, typo: 'oops' }
options.assert_valid_keys(:default, :encryption_key)
# => ArgumentError: Unknown key: :typo. Valid keys are: :default, :encryption_key
```

---

### Q2: Does `options.assert_valid_keys(:default, :encryption_key)` check if default option has an encryption_key field?

**Answer:** **No!** It's a common misunderstanding.

**What it actually checks:**
- The `options` hash can **ONLY** contain keys from the whitelist: `[:default, :encryption_key]`
- It does **NOT** check if `:default` has `:encryption_key` inside it

**Valid examples:**
```ruby
# ✅ Only :default
preference :amount, :decimal, default: 0
# options = { default: 0 }

# ✅ Only :encryption_key
preference :key, :encrypted_string, encryption_key: 'secret'
# options = { encryption_key: 'secret' }

# ✅ Both
preference :key, :encrypted_string, default: 'test', encryption_key: 'secret'
# options = { default: 'test', encryption_key: 'secret' }

# ✅ Neither (empty hash)
preference :amount, :decimal
# options = {}

# ❌ Invalid key
preference :amount, :decimal, typo: 'oops'
# Raises: Unknown key: :typo
```

**Think of it as:** A whitelist validator that says "options can ONLY have these keys, nothing else"

---

### Q3: Is `preference :amount, :decimal, default: 0` calling the preference method defined in the module?

**Answer:** **Yes!** It's a class method call.

**The Flow:**

```ruby
# 1. You include Persistable
class Calculator < Spree::Base
  include Spree::Preferences::Persistable
end

# 2. Persistable includes Preferable
# 3. Preferable extends PreferableClassMethods (adds class methods)
# 4. Now Calculator has the preference class method

# 5. When you write this in a subclass:
class Calculator::FlatRate < Calculator
  preference :amount, :decimal, default: 0
  # ↑ This calls Calculator.preference(:amount, :decimal, {default: 0})
end
```

**Proof:**
```ruby
Calculator.respond_to?(:preference)  # => true
Calculator.method(:preference).owner # => Spree::Preferences::PreferableClassMethods
```

**It's a class-level DSL method** that runs during class definition and dynamically creates instance methods!

---

### Q4: Can we pass `default: {:default}` (a hash as default)?

**Answer:** **Yes!** You can pass any Ruby value as `default:`.

**Examples:**
```ruby
# String
preference :name, :string, default: 'hello'

# Number
preference :amount, :decimal, default: 0

# Boolean
preference :enabled, :boolean, default: true

# Array
preference :items, :array, default: ['item1', 'item2']

# Hash (what you asked about)
preference :config, :hash, default: { key: 'value' }

# Hash with :default as a key
preference :settings, :hash, default: { default: true, custom: false }

# Proc (for dynamic defaults)
preference :currency, :string, default: ->{ Spree::Config[:currency] }

# Complex nested structure
preference :data, :hash, default: { nested: { deep: { value: 123 } } }
```

**Important:** The type parameter should match the default value type.

---

### Q5: Given is a hash, why are we wrapping it in a `proc`?

**Answer:** To prevent **shared mutable state** between instances.

**The Problem Without `proc`:**
```ruby
# WITHOUT proc (BAD):
DEFAULT_CONFIG = { rate: 5.0 }  # One object in memory

calc1 = Calculator.new
calc2 = Calculator.new

calc1.config[:rate] = 10.0
calc2.config[:rate]  # => 10.0 😱 Both share the SAME object!
```

**The Solution With `proc`:**
```ruby
# WITH proc (GOOD):
default = proc { { rate: 5.0 } }  # Creates NEW hash each time

calc1.preferred_config  # Calls proc, gets NEW hash
calc2.preferred_config  # Calls proc, gets ANOTHER NEW hash

# Now they're independent!
calc1.config[:rate] = 10.0
calc2.config[:rate]  # => 5.0 ✅ Unaffected!
```

**Three Benefits:**

1. **Prevents Shared Mutable State** - Each instance gets its own copy
2. **Allows Dynamic Defaults** - Can evaluate at runtime
3. **Lazy Evaluation** - Only executed when first accessed

**Memory Diagram:**
```
Without proc (shared reference):
┌─────────────────┐
│ { rate: 5.0 }   │ ← ONE object
└─────────────────┘
       ↑     ↑
    calc1  calc2  ← Both point to same object

With proc (independent objects):
┌─────────────────┐      ┌─────────────────┐
│ { rate: 5.0 }   │      │ { rate: 5.0 }   │ ← TWO objects
└─────────────────┘      └─────────────────┘
       ↑                        ↑
    calc1                    calc2  ← Independent!
```

---

### Q6: What is `instance_exec`? Why use `*`? Why use `&`?

**Answer:** Three important Ruby concepts work together here.

#### `instance_exec` - Executes block in object's context

Changes `self` inside the block to be the receiver object.

```ruby
class Calculator
  def initialize
    @amount = 100
  end
end

calc = Calculator.new

# Normal proc - can't access @amount
my_proc = proc { @amount }
my_proc.call  # => nil

# instance_exec - can access @amount!
calc.instance_exec(&my_proc)  # => 100
```

#### `*` (Splat) - Unpacks array into arguments

```ruby
args = [1, 2, 3]

# Without splat
method(args)   # Passes [1, 2, 3] as ONE argument

# With splat
method(*args)  # Passes 1, 2, 3 as THREE arguments
```

**In the code:**
```ruby
context_for_default  # => []

instance_exec(*context_for_default, &default)
# Same as:
instance_exec(*[], &default)
# Same as:
instance_exec(&default)  # No arguments
```

**Why?** Allows subclasses to override `context_for_default` to pass arguments:
```ruby
def context_for_default
  [self, Time.now]  # Pass context to the proc
end

preference :label, :string, default: ->(obj, time) { 
  "#{obj.class} at #{time}" 
}
```

#### `&` - Converts Proc to Block

```ruby
# Method expects a BLOCK
def some_method(&block)
  block.call
end

my_proc = proc { "hello" }

# Must use & to convert proc to block
some_method(&my_proc)
```

**In the code:**
```ruby
default = proc { 0 }

instance_exec(*context_for_default, &default)
#                                   ↑
#                          Converts proc to block
```

**Summary:**
```ruby
instance_exec(*context_for_default, &default)
#    ↑             ↑                    ↑
#    |             |                    Convert proc to block
#    |             Unpack array into arguments
#    Execute in context of self
```

---

### Q7: Is `instance_exec(&default)` the same as `instance_exec() { ... }`? Does it yield and pass arguments?

**Answer:** **Yes to all!**

#### They're Equivalent

```ruby
# Using &proc
instance_exec(*context_for_default, &default)

# Using do...end directly
instance_exec(*context_for_default) do
  # ... whatever is in default proc
end
```

#### Arguments Flow to the Block

```ruby
instance_exec(arg1, arg2, &block)
#             ↑     ↑      ↑
#             └─────┴──────┘
#          Passed TO the block

# Block receives them:
instance_exec(5, 10) { |a, b| a + b }  # => 15
```

#### Complete Flow Example

```ruby
# When you access preferred_amount:
calc.preferred_amount

# 1. Getter method executes
def preferred_amount
  value = preferences.fetch(:amount) do
    # 2. If not in preferences hash...
    
    context_for_default  # => []
    default              # => proc { 0 }
    
    # 3. Execute the proc in instance context
    instance_exec(*[], &default)
    # Same as:
    instance_exec() { 0 }
    
    # 4. Returns 0
  end
end
```

#### With Arguments Example

```ruby
def context_for_default
  [self, Time.now]
end

default = proc { |obj, time| "#{obj.class} at #{time}" }

instance_exec(*context_for_default, &default)
# Unpacks to:
instance_exec(self, Time.now) { |obj, time| "#{obj.class} at #{time}" }
#             ↑     ↑            ↑     ↑
#             └─────┴────────────┴─────┘
#                Arguments passed to block
```

#### Key Difference from `proc.call`

```ruby
class Calculator
  def initialize
    @rate = 10
  end
end

calc = Calculator.new
my_proc = proc { @rate }

# Regular call - original context
my_proc.call  # => nil (no @rate here)

# instance_exec - receiver's context
calc.instance_exec(&my_proc)  # => 10 (can access calc's @rate!)
```

---

## Design Pattern Summary

### The Preference System Pattern

**Key Components:**

1. **Splat Operator (`*`)** - Flexible argument passing
2. **Block Conversion (`&`)** - Proc ↔ Block conversion
3. **Lazy Evaluation** - Wrap values in procs
4. **Context Switching** - `instance_exec` for accessing instance variables
5. **Dynamic Method Creation** - `define_method` at runtime

**Pattern Flow:**
```
Class Definition
    ↓
preference :name, :type, default: value
    ↓
Wrapped in proc { value }
    ↓
define_method :preferred_name
    ↓
instance_exec(*args, &proc)
    ↓
Returns value (in instance context)
```

---

## Coding Exercises

### Exercise 1: Configuration System with Context

**Goal:** Build a configuration system that supports dynamic defaults based on environment and user context.

**Requirements:**

1. Create a `Configurable` module that can be included in classes
2. Provide a `config` class method that defines configuration options
3. Support static and dynamic defaults
4. Pass user context to dynamic defaults
5. Prevent shared mutable state

**Starter Code:**

```ruby
module Configurable
  extend ActiveSupport::Concern
  
  included do
    # Your code here
  end
  
  # Add your implementation
end

class ApiClient
  include Configurable
  
  attr_reader :user_id, :environment
  
  def initialize(user_id:, environment: :production)
    @user_id = user_id
    @environment = environment
  end
  
  # Define configurations
  config :timeout, :integer, default: 30
  config :retry_count, :integer, default: 3
  config :base_url, :string, default: ->(client) { 
    client.environment == :production ? 
      "https://api.prod.com" : 
      "https://api.dev.com" 
  }
  config :headers, :hash, default: ->(client) {
    {
      'User-Agent' => "ApiClient/#{client.user_id}",
      'X-Environment' => client.environment.to_s
    }
  }
end

# Expected Usage:
client1 = ApiClient.new(user_id: 123, environment: :production)
client1.timeout  # => 30
client1.base_url # => "https://api.prod.com"
client1.headers  # => { 'User-Agent' => 'ApiClient/123', 'X-Environment' => 'production' }

client2 = ApiClient.new(user_id: 456, environment: :development)
client2.base_url # => "https://api.dev.com"
client2.headers  # => { 'User-Agent' => 'ApiClient/456', 'X-Environment' => 'development' }

# Test shared state prevention
client1.headers[:custom] = 'value1'
client2.headers[:custom]  # => nil (should be independent)
```

**Your Task:**

Implement the `Configurable` module with:

1. A `config(name, type, options = {})` class method
2. Getter methods for each config (e.g., `timeout`, `base_url`)
3. Support for both static values and procs as defaults
4. Use `instance_exec` to evaluate dynamic defaults with the instance as context
5. Prevent shared mutable objects between instances

**Hints:**

- Use `define_method` to create getters dynamically
- Wrap defaults in procs (even static ones)
- Use `instance_exec(&default_proc)` to evaluate in instance context
- Store evaluated configs in an instance variable to cache them
- For procs that need instance access, pass `self` as context

---

### Exercise 2: Rule Engine with Block Execution

**Goal:** Create a rule engine that validates objects using rules defined with blocks, supports passing validation context, and uses splat/block operators.

**Requirements:**

1. Create a `Validatable` module
2. Support defining validation rules with blocks
3. Pass validation context (errors array, metadata) to blocks
4. Execute blocks in the context of the object being validated
5. Collect and report all validation errors

**Starter Code:**

```ruby
module Validatable
  extend ActiveSupport::Concern
  
  included do
    # Your code here
  end
  
  class_methods do
    # Add rule definition method
  end
  
  # Add validation execution method
end

class Product
  include Validatable
  
  attr_accessor :name, :price, :stock
  
  def initialize(name:, price:, stock:)
    @name = name
    @price = price
    @stock = stock
  end
  
  # Define validation rules
  validate :name_presence do |errors, metadata|
    if @name.nil? || @name.empty?
      errors << "Name cannot be blank"
    end
  end
  
  validate :price_positive do |errors, metadata|
    if @price.nil? || @price <= 0
      errors << "Price must be positive"
    end
  end
  
  validate :stock_availability do |errors, metadata|
    if metadata[:check_stock] && @stock < metadata[:minimum_stock]
      errors << "Stock below minimum: #{@stock} < #{metadata[:minimum_stock]}"
    end
  end
end

# Expected Usage:
product = Product.new(name: "Widget", price: 10, stock: 5)

# Valid product
result = product.validate
result.valid?   # => true
result.errors   # => []

# Invalid product
bad_product = Product.new(name: "", price: -5, stock: 2)
result = bad_product.validate(check_stock: true, minimum_stock: 10)
result.valid?   # => false
result.errors   # => ["Name cannot be blank", "Price must be positive", "Stock below minimum: 2 < 10"]
```

**Your Task:**

Implement the `Validatable` module with:

1. A `validate(name, &block)` class method to define rules
2. A `validate(**metadata)` instance method to run all validations
3. Return a result object with `valid?` and `errors` methods
4. Use `instance_exec` to run validation blocks in the product's context
5. Use splat operator to pass metadata to validation blocks

**Hints:**

- Store validation blocks in a class instance variable array
- Create a `ValidationResult` class to hold errors
- Use `instance_exec(*args, &block)` to pass errors and metadata
- Each block should receive `|errors, metadata|` parameters
- Blocks should have access to instance variables (`@name`, `@price`, etc.)

---

## Solutions

### Exercise 1 Solution

<details>
<summary>Click to reveal solution</summary>

```ruby
module Configurable
  extend ActiveSupport::Concern
  
  included do
    # Initialize storage for config values
    def configs
      @configs ||= {}
    end
  end
  
  class_methods do
    def defined_configs
      @defined_configs ||= []
    end
    
    def config(name, type, options = {})
      # Validate options
      options.assert_valid_keys(:default)
      
      # Store config name
      defined_configs << name
      
      # Wrap default in proc
      default = options[:default]
      default_proc = default.is_a?(Proc) ? default : proc { default }
      
      # Create getter method
      define_method(name) do
        # Check if already computed
        return configs[name] if configs.key?(name)
        
        # Evaluate default in instance context
        value = instance_exec(self, &default_proc)
        
        # Deep dup for mutable objects to prevent sharing
        value = value.dup if value.respond_to?(:dup) && ![TrueClass, FalseClass, NilClass, Integer, Float, Symbol].include?(value.class)
        
        # Cache the value
        configs[name] = value
      end
      
      # Create setter method
      define_method("#{name}=") do |value|
        configs[name] = value
      end
    end
  end
  
  # Clear cached configs
  def clear_configs!
    @configs = {}
  end
end

# Test it
class ApiClient
  include Configurable
  
  attr_reader :user_id, :environment
  
  def initialize(user_id:, environment: :production)
    @user_id = user_id
    @environment = environment
  end
  
  config :timeout, :integer, default: 30
  config :retry_count, :integer, default: 3
  config :base_url, :string, default: ->(client) { 
    client.environment == :production ? 
      "https://api.prod.com" : 
      "https://api.dev.com" 
  }
  config :headers, :hash, default: ->(client) {
    {
      'User-Agent' => "ApiClient/#{client.user_id}",
      'X-Environment' => client.environment.to_s
    }
  }
end

# Test
client1 = ApiClient.new(user_id: 123, environment: :production)
puts client1.timeout       # => 30
puts client1.base_url      # => "https://api.prod.com"
p client1.headers          # => { 'User-Agent' => 'ApiClient/123', 'X-Environment' => 'production' }

client2 = ApiClient.new(user_id: 456, environment: :development)
puts client2.base_url      # => "https://api.dev.com"

# Test independent state
client1.headers[:custom] = 'value1'
puts client2.headers[:custom]  # => nil (independent!)
```

</details>

---

### Exercise 2 Solution

<details>
<summary>Click to reveal solution</summary>

```ruby
module Validatable
  extend ActiveSupport::Concern
  
  class ValidationResult
    attr_reader :errors
    
    def initialize
      @errors = []
    end
    
    def valid?
      errors.empty?
    end
    
    def add_error(message)
      errors << message
    end
  end
  
  class_methods do
    def validations
      @validations ||= []
    end
    
    def validate(name, &block)
      validations << { name: name, block: block }
    end
  end
  
  def validate(**metadata)
    result = ValidationResult.new
    
    # Run each validation in instance context
    self.class.validations.each do |validation|
      # Execute block with errors and metadata
      instance_exec(result.errors, metadata, &validation[:block])
    end
    
    result
  end
end

# Test it
class Product
  include Validatable
  
  attr_accessor :name, :price, :stock
  
  def initialize(name:, price:, stock:)
    @name = name
    @price = price
    @stock = stock
  end
  
  validate :name_presence do |errors, metadata|
    if @name.nil? || @name.empty?
      errors << "Name cannot be blank"
    end
  end
  
  validate :price_positive do |errors, metadata|
    if @price.nil? || @price <= 0
      errors << "Price must be positive"
    end
  end
  
  validate :stock_availability do |errors, metadata|
    if metadata[:check_stock] && @stock < metadata[:minimum_stock]
      errors << "Stock below minimum: #{@stock} < #{metadata[:minimum_stock]}"
    end
  end
end

# Test valid product
product = Product.new(name: "Widget", price: 10, stock: 5)
result = product.validate
puts result.valid?    # => true
p result.errors       # => []

# Test invalid product
bad_product = Product.new(name: "", price: -5, stock: 2)
result = bad_product.validate(check_stock: true, minimum_stock: 10)
puts result.valid?    # => false
p result.errors       
# => ["Name cannot be blank", "Price must be positive", "Stock below minimum: 2 < 10"]
```

</details>

---

## Key Takeaways

### Pattern Elements to Master

1. **Splat Operator (`*`)**
   - Unpacks arrays into arguments
   - Provides flexibility in argument passing
   - Enables extensibility through context

2. **Block Operator (`&`)**
   - Converts Proc ↔ Block
   - Required when passing procs to methods expecting blocks
   - Used with `instance_exec`, `define_method`, etc.

3. **`instance_exec`**
   - Executes blocks in object's context
   - Enables access to private methods and instance variables
   - Passes arguments to the block

4. **Lazy Evaluation with Procs**
   - Prevents shared mutable state
   - Enables dynamic evaluation
   - Provides consistent interface for static and dynamic defaults

5. **Dynamic Method Definition**
   - `define_method` creates methods at runtime
   - Enables DSL creation
   - Allows metaprogramming patterns

### Design Benefits

- **Flexibility** - Support both static and dynamic configurations
- **Safety** - Prevent shared state bugs
- **DRY** - Reduce code duplication through metaprogramming
- **Expressiveness** - Create readable DSLs
- **Extensibility** - Easy to add new features through context

---

## Further Practice

Try these additional challenges:

1. **Add Type Coercion** - Extend Exercise 1 to automatically convert types (string to integer, etc.)

2. **Add Caching** - Implement memoization for expensive dynamic defaults

3. **Add Nested Configs** - Support namespaced configurations like `config.database.host`

4. **Add Inheritance** - Make validations inheritable with ability to override in subclasses

5. **Add Conditional Validations** - Support `:if` and `:unless` options on validations

---

**Created:** October 21, 2025  
**Topic:** Understanding Ruby Metaprogramming Patterns in Solidus Preferences System

