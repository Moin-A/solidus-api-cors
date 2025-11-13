# Spree::Preferences::Persistable - Complete Source Code

This document contains the complete source code for the `Spree::Preferences::Persistable` module and its dependencies, extracted from the Solidus Core gem for easy reference.

**Source Location:** `solidus_core-4.5.1/lib/spree/preferences/`

---

## Module Hierarchy

```
Persistable (entry point - what you include)
    ↓
    includes Preferable (main logic)
        ↓
        extends PreferableClassMethods (class-level methods)
```

---

## Understanding `include Spree::Preferences::Persistable`

### What Happens When You Write This Line

```ruby
class Calculator < Spree::Base
  include Spree::Preferences::Persistable  # ← This line
end
```

### The `include` Mechanism

`include` is a Ruby keyword that mixes a module's **instance methods** into a class.

**Before include:**
```ruby
class Calculator < Spree::Base
  # Only has methods from Spree::Base and Object
end

calc = Calculator.new
calc.methods # => [methods from Object, ActiveRecord::Base, Spree::Base]
```

**After include:**
```ruby
class Calculator < Spree::Base
  include Spree::Preferences::Persistable
  # Now has all instance methods from the module
end

calc = Calculator.new
calc.methods # => [previous methods + get_preference, set_preference, has_preference?, etc.]
```

### What Gets Mixed In

When `include Spree::Preferences::Persistable` executes:

**1. Ruby's Include Hook Fires**
```ruby
# Inside Persistable module:
module Persistable
  extend ActiveSupport::Concern  # ← This enhances the include behavior
  
  included do  # ← This block runs when module is included
    # Code here executes in the context of the including class (Calculator)
  end
end
```

**2. The `included` Block Runs**

The code inside `included do` executes **as if it were written directly in your class**:

```ruby
# When you write:
class Calculator < Spree::Base
  include Spree::Preferences::Persistable
end

# Ruby effectively does this:
class Calculator < Spree::Base
  # From Persistable's included block:
  include Spree::Preferences::Preferable
  
  serialize :preferences, type: Hash, coder: YAML
  
  after_initialize :initialize_preference_defaults
  
  # Plus all instance methods from Persistable and Preferable
  def get_preference(name)
    # ...
  end
  
  def set_preference(name, value)
    # ...
  end
  
  # etc.
end
```

**3. Chain Reaction**

```
include Persistable
    ↓ (triggers)
included block executes
    ↓ (which does)
include Preferable
    ↓ (which does)
extend PreferableClassMethods
    ↓ (which adds)
preference() class method
```

### The Complete Inclusion Chain

```ruby
# Step 1: You include Persistable
class Calculator < Spree::Base
  include Spree::Preferences::Persistable
end

# Step 2: Persistable's included block runs
# (adds to Calculator class)
  include Spree::Preferences::Preferable  # ← Includes another module
  serialize :preferences, type: Hash, coder: YAML
  after_initialize :initialize_preference_defaults

# Step 3: Preferable's included block runs  
# (adds to Calculator class)
  extend Spree::Preferences::PreferableClassMethods  # ← Adds class methods

# Step 4: Calculator now has everything:
Calculator.methods # includes: .preference, .defined_preferences
Calculator.new.methods # includes: get_preference, set_preference, preferred_*
```

### Visual Breakdown

```
┌─────────────────────────────────────────────────────────────┐
│ YOUR CODE                                                     │
│ class Calculator < Spree::Base                               │
│   include Spree::Preferences::Persistable                    │
│ end                                                           │
└─────────────────────────────────────────────────────────────┘
                         ↓ include
┌─────────────────────────────────────────────────────────────┐
│ PERSISTABLE MODULE                                            │
│ module Spree::Preferences::Persistable                       │
│   extend ActiveSupport::Concern                              │
│                                                               │
│   included do  ← THIS BLOCK RUNS IN Calculator's CONTEXT    │
│     include Spree::Preferences::Preferable                   │
│     serialize :preferences, type: Hash, coder: YAML          │
│     after_initialize :initialize_preference_defaults         │
│   end                                                         │
│                                                               │
│   def initialize_preference_defaults  ← INSTANCE METHOD      │
│     # This becomes Calculator#initialize_preference_defaults │
│   end                                                         │
│ end                                                           │
└─────────────────────────────────────────────────────────────┘
                         ↓ triggers include
┌─────────────────────────────────────────────────────────────┐
│ PREFERABLE MODULE                                             │
│ module Spree::Preferences::Preferable                        │
│   extend ActiveSupport::Concern                              │
│                                                               │
│   included do  ← THIS ALSO RUNS IN Calculator's CONTEXT     │
│     extend Spree::Preferences::PreferableClassMethods        │
│   end                                                         │
│                                                               │
│   def get_preference(name)  ← INSTANCE METHOD                │
│   def set_preference(name, value)  ← INSTANCE METHOD         │
│   # etc.                                                      │
│ end                                                           │
└─────────────────────────────────────────────────────────────┘
                         ↓ triggers extend
┌─────────────────────────────────────────────────────────────┐
│ PREFERABLE CLASS METHODS MODULE                               │
│ module Spree::Preferences::PreferableClassMethods            │
│                                                               │
│   def preference(name, type, options = {})  ← CLASS METHOD   │
│     # This becomes Calculator.preference                     │
│     define_method "preferred_#{name}" do                     │
│       # Creates instance method                              │
│     end                                                       │
│   end                                                         │
│                                                               │
│   def defined_preferences  ← CLASS METHOD                    │
│     # This becomes Calculator.defined_preferences            │
│   end                                                         │
│ end                                                           │
└─────────────────────────────────────────────────────────────┘
```

### Result: Calculator Class Now Has

**Instance Methods** (from `include`):
```ruby
calc = Calculator.new
calc.get_preference(:amount)
calc.set_preference(:amount, 10)
calc.has_preference?(:amount)
calc.defined_preferences
calc.default_preferences
calc.initialize_preference_defaults  # private
calc.convert_preference_value(...)   # private
```

**Class Methods** (from `extend`):
```ruby
Calculator.preference(:amount, :decimal, default: 0)
Calculator.defined_preferences
Calculator.preference_getter_method(:amount)
Calculator.preference_setter_method(:amount)
Calculator.allowed_admin_form_preference_types
```

**ActiveRecord Enhancements**:
```ruby
# From serialize call:
Calculator.new.preferences  # => {} (Hash, not nil)
# Automatically serialized to/from YAML in database

# From after_initialize:
Calculator.new  # Automatically calls initialize_preference_defaults
```

### The Power of `extend ActiveSupport::Concern`

Without `ActiveSupport::Concern`:
```ruby
module MyModule
  def self.included(base)
    base.include OtherModule
    base.extend ClassMethods
  end
  
  module ClassMethods
    # ...
  end
end
```

With `ActiveSupport::Concern` (what Solidus uses):
```ruby
module MyModule
  extend ActiveSupport::Concern
  
  included do  # ← Cleaner!
    include OtherModule
  end
  
  class_methods do  # ← Or this for class methods
    # ...
  end
end
```

It's syntactic sugar that makes module composition cleaner and handles dependency ordering automatically.

---

## 1. Persistable Module (Entry Point)

**File:** `spree/preferences/persistable.rb`

```ruby
# frozen_string_literal: true

module Spree
  module Preferences
    module Persistable
      extend ActiveSupport::Concern

      included do
        # Include the Preferable module (where all the magic happens)
        include Spree::Preferences::Preferable

        # Serialize the preferences column as a Hash using YAML
        # This is what stores all preferences in the database
        if Rails.gem_version >= Gem::Version.new('7.1')
          serialize :preferences, type: Hash, coder: YAML
        else
          serialize :preferences, Hash, coder: YAML
        end

        # After creating a new instance, initialize preferences with defaults
        after_initialize :initialize_preference_defaults
      end

      private

      # Called after object initialization
      # Merges default preferences with any existing preferences
      # This ensures defaults are set even before saving to database
      def initialize_preference_defaults
        if has_attribute?(:preferences)
          # default_preferences comes from Preferable module
          # This merges defaults but keeps any already-set values
          self.preferences = default_preferences.merge(preferences)
        end
      end
    end
  end
end
```

### What This Module Does:

1. **Includes Preferable** - Gets all the preference functionality
2. **Serializes preferences column** - Tells Rails to convert the hash to YAML
3. **Initializes defaults** - Sets default values when creating new records

---

## 2. Preferable Module (Core Logic)

**File:** `spree/preferences/preferable.rb`

```ruby
# frozen_string_literal: true

require 'spree/preferences/preferable_class_methods'
require 'active_support/concern'
require 'active_support/core_ext/hash/keys'

module Spree
  module Preferences
    # Preferable allows defining preference accessor methods.
    #
    # A class including Preferable must implement #preferences which should return
    # an object responding to .fetch(key), []=(key, val), and .delete(key).
    # If #preferences is initialized with `default_preferences` and one of the
    # preferences is another preference, it will cause a stack level too deep error.
    # To avoid it do not memoize #preferences.
    #
    # It may also define a `#context_for_default` method. It should return an
    # array with the arguments to be provided to a proc used as the `default:`
    # keyword for a preference.
    #
    # The generated writer method performs typecasting before assignment into the
    # preferences object.
    #
    # Examples:
    #
    #   # Spree::Base includes Preferable and defines preferences as a serialized
    #   # column.
    #   class Settings < Spree::Base
    #     preference :color,       :string,  default: 'red'
    #     preference :temperature, :integer, default: 21
    #   end
    #
    #   s = Settings.new
    #   s.preferred_color # => 'red'
    #   s.preferred_temperature # => 21
    #
    #   s.preferred_color = 'blue'
    #   s.preferred_color # => 'blue'
    #
    #   # Typecasting is performed on assignment
    #   s.preferred_temperature = '24'
    #   s.preferred_color # => 24
    #
    #   # Modifications have been made to the .preferences hash
    #   s.preferences #=> {color: 'blue', temperature: 24}
    #
    #   # Save the changes. All handled by activerecord
    #   s.save!
    #
    # Each preference gets rendered as a form field in Solidus backend.
    #
    # As not all supported preference types are representable as a form field, only
    # some of them get rendered per default. Arrays and Hashes for instance are
    # supported preference field types, but do not represent well as a form field.
    #
    # Overwrite +allowed_admin_form_preference_types+ in your class if you want to
    # provide more fields. If you do so, you also need to provide a preference field
    # partial that lives in:
    #
    # +app/views/spree/admin/shared/preference_fields/+
    #
    module Preferable
      extend ActiveSupport::Concern

      included do
        # Add class methods from PreferableClassMethods
        # This gives access to the `preference` class method
        extend Spree::Preferences::PreferableClassMethods
      end

      # Get a preference
      # @param name [#to_sym] name of preference
      # @return [Object] The value of preference +name+
      def get_preference(name)
        has_preference! name
        send self.class.preference_getter_method(name)
      end

      # Set a preference
      # @param name [#to_sym] name of preference
      # @param value [Object] new value for preference +name+
      def set_preference(name, value)
        has_preference! name
        send self.class.preference_setter_method(name), value
      end

      # @param name [#to_sym] name of preference
      # @return [Symbol] The type of preference +name+
      def preference_type(name)
        has_preference! name
        send self.class.preference_type_getter_method(name)
      end

      # @param name [#to_sym] name of preference
      # @return [Object] The default for preference +name+
      def preference_default(name)
        has_preference! name
        send self.class.preference_default_getter_method(name)
      end

      # Raises an exception if the +name+ preference is not defined on this class
      # @param name [#to_sym] name of preference
      def has_preference!(name)
        raise NoMethodError.new "#{name} preference not defined" unless has_preference? name
      end

      # @param name [#to_sym] name of preference
      # @return [Boolean] if preference exists on this class
      def has_preference?(name)
        defined_preferences.include?(name.to_sym)
      end

      # @return [Array<Symbol>] All preferences defined on this class
      def defined_preferences
        self.class.defined_preferences
      end

      # @return [Hash{Symbol => Object}] Default for all preferences defined on this class
      # This may raise an infinite loop error if any of the defaults are
      # dependent on other preferences defaults.
      def default_preferences
        Hash[
          defined_preferences.map do |preference|
            [preference, preference_default(preference)]
          end
        ]
      end

      # Preference names representable as form fields in Solidus backend
      #
      # Not all preferences are representable as a form field.
      #
      # Arrays and Hashes for instance are supported preference field types,
      # but do not represent well as a form field.
      #
      # As these kind of preferences are mostly developer facing
      # and not admin facing we should not render them.
      #
      # Overwrite +allowed_admin_form_preference_types+ in your class that
      # includes +Spree::Preferable+ if you want to provide more fields.
      # If you do so, you also need to provide a preference field partial
      # that lives in:
      #
      # +app/views/spree/admin/shared/preference_fields/+
      #
      # @return [Array]
      def admin_form_preference_names
        defined_preferences.keep_if do |type|
          preference_type(type).in? self.class.allowed_admin_form_preference_types
        end
      end

      private

      # Convert value to the appropriate type
      # This is called by the setter method before storing the value
      def convert_preference_value(value, type, preference_encryptor = nil)
        return nil if value.nil?
        case type
        when :string, :text
          value.to_s
        when :encrypted_string
          preference_encryptor.encrypt(value.to_s)
        when :password
          value.to_s
        when :decimal
          begin
            value.to_s.to_d
          rescue ArgumentError
            BigDecimal(0)
          end
        when :integer
          value.to_i
        when :boolean
          if !value ||
             value.to_s =~ /\A(f|false|0|^)\Z/i ||
             (value.respond_to?(:empty?) && value.empty?)
            false
          else
            true
          end
        when :array
          raise TypeError, "Array expected got #{value.inspect}" unless value.is_a?(Array)
          value
        when :hash
          raise TypeError, "Hash expected got #{value.inspect}" unless value.is_a?(Hash)
          value
        else
          value
        end
      end

      # Override this in your class to provide context for default proc evaluation
      # Returns an array of arguments passed to the default proc
      def context_for_default
        [].freeze
      end
    end
  end
end
```

### What This Module Provides:

**Instance Methods:**
- `get_preference(name)` - Get a preference value
- `set_preference(name, value)` - Set a preference value  
- `preference_type(name)` - Get the type of a preference
- `preference_default(name)` - Get the default value
- `has_preference?(name)` - Check if preference exists
- `defined_preferences` - List all preferences
- `default_preferences` - Hash of all defaults
- `convert_preference_value` - Type coercion logic

---

## 3. PreferableClassMethods Module (The Magic)

**File:** `spree/preferences/preferable_class_methods.rb`

```ruby
# frozen_string_literal: true

require 'spree/encryptor'

module Spree::Preferences
  module PreferableClassMethods
    # Default types that can be edited in admin forms
    DEFAULT_ADMIN_FORM_PREFERENCE_TYPES = %i(
      boolean
      decimal
      integer
      password
      string
      text
      encrypted_string
    )

    # Base method that gets overridden as preferences are defined
    def defined_preferences
      []
    end

    # ⭐ THE MAIN METHOD - Defines a preference and creates methods
    # This is what gets called when you write:
    #   preference :amount, :decimal, default: 0
    #
    # @param name [Symbol] The preference name (e.g., :amount)
    # @param type [Symbol] The preference type (e.g., :decimal, :string, :boolean)
    # @param options [Hash] Options including :default and :encryption_key
    def preference(name, type, options = {})
      options.assert_valid_keys(:default, :encryption_key)

      # Handle encrypted string preferences
      if type == :encrypted_string
        preference_encryptor = preference_encryptor(options)
        options[:default] = preference_encryptor.encrypt(options[:default])
      end

      # Wrap the default value in a proc (or keep it as proc if already one)
      # This allows lazy evaluation of defaults
      default = begin
                  given = options[:default]
                  if given.is_a?(Proc)
                    given
                  else
                    proc { given }
                  end
                end

      # The defined preferences on a class are all those defined directly on
      # that class as well as those defined on ancestors.
      # We store these as a class instance variable on each class which has a
      # preference. super() collects preferences defined on ancestors.
      singleton_preferences = (@defined_singleton_preferences ||= [])
      singleton_preferences << name.to_sym

      # Override defined_preferences to include this new preference
      define_singleton_method :defined_preferences do
        super() + singleton_preferences
      end

      # ⭐ DEFINE GETTER METHOD: preferred_#{name}
      # Example: preferred_amount
      # This method:
      # 1. Tries to fetch from preferences hash
      # 2. Falls back to default if not found
      # 3. Decrypts if needed
      define_method preference_getter_method(name) do
        value = preferences.fetch(name) do
          instance_exec(*context_for_default, &default)
        end
        value = preference_encryptor.decrypt(value) if preference_encryptor.present?
        value
      end

      # ⭐ DEFINE SETTER METHOD: preferred_#{name}=
      # Example: preferred_amount=
      # This method:
      # 1. Converts value to correct type
      # 2. Stores in preferences hash
      # 3. Marks as dirty for ActiveRecord
      define_method preference_setter_method(name) do |value|
        value = convert_preference_value(value, type, preference_encryptor)
        preferences[name] = value

        # If this is an activerecord object, we need to inform
        # ActiveRecord::Dirty that this value has changed, since this is an
        # in-place update to the preferences hash.
        preferences_will_change! if respond_to?(:preferences_will_change!)
      end

      # ⭐ DEFINE DEFAULT GETTER: preferred_#{name}_default
      # Example: preferred_amount_default
      # Returns the default value
      define_method preference_default_getter_method(name) do
        instance_exec(*context_for_default, &default)
      end

      # ⭐ DEFINE TYPE GETTER: preferred_#{name}_type
      # Example: preferred_amount_type
      # Returns the type symbol
      define_method preference_type_getter_method(name) do
        type
      end
    end

    # Generate getter method name
    # @example preference_getter_method(:amount) => :preferred_amount
    def preference_getter_method(name)
      "preferred_#{name}".to_sym
    end

    # Generate setter method name
    # @example preference_setter_method(:amount) => :preferred_amount=
    def preference_setter_method(name)
       "preferred_#{name}=".to_sym
    end

    # Generate default getter method name
    # @example preference_default_getter_method(:amount) => :preferred_amount_default
    def preference_default_getter_method(name)
      "preferred_#{name}_default".to_sym
    end

    # Generate type getter method name
    # @example preference_type_getter_method(:amount) => :preferred_amount_type
    def preference_type_getter_method(name)
      "preferred_#{name}_type".to_sym
    end

    # Create an encryptor for encrypted preferences
    def preference_encryptor(options)
      key = options[:encryption_key] ||
            ENV['SOLIDUS_PREFERENCES_MASTER_KEY'] ||
            Rails.application.credentials.secret_key_base

      Spree::Encryptor.new(key)
    end

    # List of preference types allowed as form fields in the Solidus admin
    #
    # Overwrite this method in your class that includes +Spree::Preferable+
    # if you want to provide more fields. If you do so, you also need to provide
    # a preference field partial that lives in:
    #
    # +app/views/spree/admin/shared/preference_fields/+
    #
    # @return [Array]
    def allowed_admin_form_preference_types
      DEFAULT_ADMIN_FORM_PREFERENCE_TYPES
    end
  end
end
```

### What This Module Provides:

**Class Methods:**
- `preference(name, type, options)` - ⭐ The DSL method that creates everything
- `defined_preferences` - List of all defined preferences
- `preference_getter_method(name)` - Helper to generate getter name
- `preference_setter_method(name)` - Helper to generate setter name
- `preference_default_getter_method(name)` - Helper for default getter
- `preference_type_getter_method(name)` - Helper for type getter
- `allowed_admin_form_preference_types` - Types usable in admin

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Include the Module                                       │
│                                                                   │
│ class Calculator < Spree::Base                                   │
│   include Spree::Preferences::Persistable                        │
│ end                                                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: What Gets Added                                          │
│                                                                   │
│ 1. Persistable includes Preferable                               │
│ 2. Preferable extends PreferableClassMethods                     │
│ 3. Preferences column gets serialized as Hash/YAML               │
│ 4. after_initialize callback added                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Define a Preference                                      │
│                                                                   │
│ class Calculator::FlatRate < Calculator                          │
│   preference :amount, :decimal, default: 0                       │
│ end                                                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: PreferableClassMethods.preference() Creates:             │
│                                                                   │
│ Instance Methods:                                                 │
│   • preferred_amount          (getter)                            │
│   • preferred_amount=         (setter)                            │
│   • preferred_amount_default  (default value)                     │
│   • preferred_amount_type     (returns :decimal)                  │
│                                                                   │
│ Class State:                                                      │
│   • Adds :amount to defined_preferences array                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: Using the Preference                                     │
│                                                                   │
│ calc = Calculator::FlatRate.new                                  │
│ calc.preferred_amount = "10.99"  # Setter called                 │
│                                                                   │
│ Inside the setter:                                                │
│ 1. convert_preference_value("10.99", :decimal, nil)              │
│    → Returns: BigDecimal("10.99")                                │
│ 2. preferences[:amount] = BigDecimal("10.99")                    │
│ 3. preferences_will_change! (marks as dirty)                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 6: Saving to Database                                       │
│                                                                   │
│ calc.save                                                         │
│                                                                   │
│ ActiveRecord:                                                     │
│ 1. Detects preferences has changed                                │
│ 2. Calls YAML.dump({ amount: BigDecimal("10.99") })             │
│ 3. Stores in preferences column:                                  │
│    "---\n:amount: '10.99'\n"                                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 7: Reading from Database                                    │
│                                                                   │
│ calc = Calculator::FlatRate.find(1)                              │
│                                                                   │
│ ActiveRecord:                                                     │
│ 1. Reads preferences column: "---\n:amount: '10.99'\n"          │
│ 2. YAML.load → { amount: BigDecimal("10.99") }                  │
│ 3. Sets @preferences = { amount: BigDecimal("10.99") }          │
│                                                                   │
│ calc.preferred_amount  # Getter called                           │
│                                                                   │
│ Inside the getter:                                                │
│ 1. preferences.fetch(:amount) { default }                        │
│ 2. Returns: BigDecimal("10.99")                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Type Conversion Details

```ruby
# From convert_preference_value method

:string, :text
  → value.to_s
  → "hello" stays "hello"
  → 123 becomes "123"

:decimal
  → value.to_s.to_d
  → "10.99" becomes BigDecimal("10.99")
  → 10 becomes BigDecimal("10")

:integer
  → value.to_i
  → "42" becomes 42
  → 42.9 becomes 42

:boolean
  → false if: nil, false, "f", "false", "0", "", []
  → true otherwise
  → "yes" becomes true
  → "0" becomes false

:array
  → Raises TypeError unless already an array
  → [1, 2, 3] stays [1, 2, 3]

:hash
  → Raises TypeError unless already a hash
  → { a: 1 } stays { a: 1 }

:password, :encrypted_string
  → Special handling with encryption
```

---

## Key Insights

### 1. **It's All Dynamic**
Every method (`preferred_amount`, `preferred_amount=`, etc.) is created at runtime using `define_method`.

### 2. **Single Column Storage**
All preferences for one record go into a single `preferences` column as serialized YAML.

### 3. **Type Safety**
The module handles type conversion automatically - you can't accidentally store a string where a decimal is expected.

### 4. **Lazy Defaults**
Defaults are wrapped in procs and only evaluated when needed, allowing dynamic defaults.

### 5. **ActiveRecord Integration**
The module properly marks the model as dirty when preferences change, ensuring ActiveRecord saves them.

### 6. **Inheritance Friendly**
Subclasses can define their own preferences that extend (not override) parent preferences.

---

## Usage Example

```ruby
# The class
class Calculator::FlatRate < Calculator
  # This ONE line...
  preference :amount, :decimal, default: 0
  
  # ...creates FOUR methods:
  # - preferred_amount
  # - preferred_amount=
  # - preferred_amount_default  
  # - preferred_amount_type
end

# Creating and using
calc = Calculator::FlatRate.new
calc.preferred_amount                    # => 0 (default)
calc.preferred_amount = "10.99"          # Type coercion happens
calc.preferred_amount                    # => BigDecimal("10.99")
calc.preferences                         # => { amount: BigDecimal("10.99") }
calc.save                                # Saves to DB as YAML
calc.reload.preferred_amount             # => BigDecimal("10.99")
```

---

**Source:** Solidus Core 4.5.1  
**Location:** `/Users/apple/.rbenv/versions/3.1.2/lib/ruby/gems/3.1.0/gems/solidus_core-4.5.1/lib/spree/preferences/`


---

## Quick Reference: Using `serialize` for Your Own Models

You can apply the same pattern outside of Solidus preferences. If your Active Record table has a single column that stores YAML (or JSON), call `serialize` on it so Rails automatically converts the stored text to a richer Ruby object:

```ruby
class Calculator < ApplicationRecord
  serialize :some_preference, Hash, coder: YAML
end
```

Now whenever you load a row:

```ruby
tool = Calculator.first
puts tool.some_preference.class # => Hash
```

Any changes you make to `tool.some_preference` are YAML-dumped back into the column when you save. This is exactly what `Spree::Preferences::Persistable` sets up for the `preferences` column on Solidus models.

> **Note:** YAML is just structured text (similar to JSON in spirit). When Rails serializes a hash to YAML, it stores that text in the column. On reload, the YAML is parsed back into the original Ruby object.
