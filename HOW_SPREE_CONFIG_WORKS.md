# Solidus Configuration Guide

## Overview

This guide explains how configuration works in Solidus, covering the singleton pattern, initialization process, and usage throughout the application.

## Table of Contents

1. [The Configuration Pattern](#the-configuration-pattern)
2. [How Spree.config Works](#how-spreeconfig-works)
3. [Initialization Process](#initialization-process)
4. [Usage Throughout the App](#usage-throughout-the-app)
5. [AppConfiguration Class](#appconfiguration-class)
6. [Role Configuration Example](#role-configuration-example)

---

## The Configuration Pattern

Solidus uses the **Singleton Pattern** for configuration. This means:

- ✅ One configuration instance exists throughout the app lifetime
- ✅ Configured once during Rails initialization
- ✅ Accessed from anywhere in the application
- ✅ Same instance returned every time

### Lifecycle

```
App Start
   ↓
config/initializers/spree.rb runs
   ↓
Configuration instance created & configured
   ↓
App Running (all requests use same instance)
   ↓
App Restart (new instance created on next boot)
```

---

## How Spree.config Works

### The Class Method Definition

```ruby
# In solidus_core/lib/spree.rb
module Spree
  class << self
    def config
      @config ||= Spree::AppConfiguration.new  # Singleton instance
      yield @config if block_given?             # Allow configuration via block
      @config                                   # Return the instance
    end
  end
end
```

### Key Mechanism: `@config ||=`

This ensures the `AppConfiguration` instance is created **only once**:

```ruby
# First call: creates new instance
Spree.config  # => Creates Spree::AppConfiguration.new

# Subsequent calls: returns existing instance
Spree.config  # => Returns same instance
Spree.config  # => Still same instance
```

### The Constant Alias

Solidus also provides `Spree::Config` as a constant:

```ruby
# Both access the same instance
Spree.config.object_id == Spree::Config.object_id  # => true

# You can use either:
Spree.config.currency
Spree::Config.currency
```

---

## Initialization Process

### In config/initializers/spree.rb

```ruby
Spree.config do |config|
  config.currency = "USD"
  config.allow_guest_checkout = true
  config.track_inventory_levels = false
  config.roles = CustomRoleConfiguration.new
end
```

### What Happens Behind the Scenes

```ruby
# Step 1: Spree.config is called with a block
Spree.config do |config|
  
  # Step 2: The AppConfiguration instance is yielded to the block
  # 'config' parameter = Spree::AppConfiguration instance
  
  # Step 3: You're calling setter methods on the instance
  config.currency = "USD"
end

# This is equivalent to:
config = Spree.config
config.currency = "USD"
```

### Why This Pattern?

Provides a clean, readable DSL for configuration:

```ruby
# ✅ Clean and readable
Spree.config do |config|
  config.currency = "USD"
  config.allow_guest_checkout = true
  config.track_inventory_levels = false
end

# ❌ Less elegant alternative
Spree.config.currency = "USD"
Spree.config.allow_guest_checkout = true
Spree.config.track_inventory_levels = false
```

---

## Usage Throughout the App

Once configured, the same instance is used everywhere:

### In Controllers

```ruby
class OrdersController < ApplicationController
  def create
    @order = Spree::Order.new
    @order.currency = Spree.config.currency
    # Uses the configured currency from initializer
  end
end
```

### In Models

```ruby
class Ability
  include CanCan::Ability
  
  def initialize(user)
    # Access role configuration
    Spree.config.roles.activate_permissions!(self, user)
  end
end
```

### In Views

```ruby
<% if Spree.config.allow_guest_checkout %>
  <%= link_to "Checkout as Guest", guest_checkout_path %>
<% end %>
```

### In Services

```ruby
class InventoryService
  def should_track?
    Spree.config.track_inventory_levels
  end
end
```

---

## AppConfiguration Class

### Structure

```ruby
# solidus_core/lib/spree/app_configuration.rb
module Spree
  class AppConfiguration
    # Define configurable attributes
    attr_accessor :currency
    attr_accessor :allow_guest_checkout
    attr_accessor :track_inventory_levels
    attr_accessor :roles
    
    def initialize
      # Set default values
      @currency = "USD"
      @allow_guest_checkout = true
      @track_inventory_levels = true
      @roles = Spree::RoleConfiguration.new
    end
    
    # Can also have custom methods
    def configured_locales
      Rails.application.config.i18n.available_locales
    end
  end
end
```

### How attr_accessor Works

```ruby
attr_accessor :currency

# Is equivalent to:
def currency
  @currency
end

def currency=(value)
  @currency = value
end
```

---

## Role Configuration Example

### The Full Flow

#### 1. RoleConfiguration Class

```ruby
# solidus_core/lib/spree/core/role_configuration.rb
module Spree
  class RoleConfiguration
    def activate_permissions!(ability, user)
      user.spree_roles.each do |role|
        permission_set = role.permission_sets.find_by(active: true)
        permission_set&.activate!(ability)
      end
    end
  end
end
```

#### 2. AppConfiguration Includes It

```ruby
module Spree
  class AppConfiguration
    attr_accessor :roles
    
    def initialize
      @roles = Spree::RoleConfiguration.new
    end
  end
end
```

#### 3. Used in Ability Class

```ruby
# app/models/ability.rb
class Ability
  include CanCan::Ability
  
  def initialize(user)
    @user = user || Spree::User.new
    
    # This calls the activate_permissions! method
    # on the RoleConfiguration instance
    activate_permission_sets
  end
  
  private
  
  def activate_permission_sets
    # Spree.config returns AppConfiguration instance
    # .roles returns RoleConfiguration instance
    # .activate_permissions! is called on RoleConfiguration
    Spree.config.roles.activate_permissions!(self, @user)
  end
end
```

#### 4. What Happens at Runtime

```ruby
# When a request comes in and Ability is initialized:

Spree.config  
# => Returns the singleton Spree::AppConfiguration instance

.roles  
# => Returns the Spree::RoleConfiguration instance

.activate_permissions!(ability, user)  
# => Calls the method to set up permissions for this user
```

---

## Key Takeaways

### The Singleton Pattern

```ruby
# Same instance everywhere
instance1 = Spree.config
instance2 = Spree.config
instance1.object_id == instance2.object_id  # => true
```

### Configuration vs Access

```ruby
# Configuration (once, during initialization)
Spree.config do |config|
  config.currency = "USD"
end

# Access (many times, throughout app)
Spree.config.currency  # => "USD"
```

### Why This Matters

1. **Performance**: Instance created once, not on every request
2. **Consistency**: Same configuration used throughout the app
3. **Simplicity**: Easy to access from anywhere
4. **Flexibility**: Easy to customize in initializers

---

## Common Patterns in Other Gems

This pattern is used widely in Ruby ecosystem:

```ruby
# Rails
Rails.application.config.time_zone = "UTC"

# Devise
Devise.setup do |config|
  config.mailer_sender = "noreply@example.com"
end

# CanCanCan (uses it for abilities)
Ability.new(user)

# Solidus
Spree.config do |config|
  config.currency = "USD"
end
```

---

## Debugging Tips

### Check Configuration in Rails Console

```ruby
# See all configuration
Spree.config.inspect

# Check specific values
Spree.config.currency
Spree.config.roles.class

# Verify singleton behavior
Spree.config.object_id
Spree::Config.object_id
```

### Find Configuration Definition

```bash
# Find where configuration is defined
bundle show solidus_core
cd $(bundle show solidus_core)
grep -r "class AppConfiguration" lib/

# Find specific configuration option
grep -r "attr_accessor :currency" lib/
```

### Common Issues

**Problem**: Configuration changes not taking effect

**Solution**: Restart your Rails server. Configuration is loaded once on app boot.

```bash
# Stop server and restart
rails s
```

---

## Summary

1. **Definition**: `Spree.config` is a class method that returns a singleton instance
2. **Initialization**: Configured once in `config/initializers/spree.rb`
3. **Usage**: Same instance accessed throughout the app via `Spree.config` or `Spree::Config`
4. **Pattern**: Standard Ruby singleton pattern using class instance variables
5. **Purpose**: Centralized, consistent configuration across the entire application

This pattern provides a clean, maintainable way to manage application-wide settings in Solidus and is a fundamental Ruby on Rails convention.