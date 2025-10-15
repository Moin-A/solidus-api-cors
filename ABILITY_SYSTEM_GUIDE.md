# Spree::Ability System - Complete Guide

## The Missing Piece: Understanding Spree::Ability

When you call `authorize! :update, @order`, how does the system know what the user can and cannot do? The answer is the **Spree::Ability** class.

---

## Definition

**`Spree::Ability`** is the central authorization class that:
1. Loads the current user
2. Loads all permission sets for the user's roles
3. Provides the `can?` and `cannot?` methods that `authorize!` uses to check permissions

---

## The Complete Code

**File: `app/models/spree/ability.rb`**

```ruby
module Spree
  class Ability
    include CanCan::Ability    # ← Gives us can/cannot/authorize! methods
    
    class_attribute :abilities
    self.abilities = Set.new    # ← Stores registered custom abilities
    
    attr_reader :user           # ← The current user
    
    # Called when: Spree::Ability.new(current_api_user)
    def initialize(current_user)
      @user = current_user || Spree.user_class.new
      
      activate_permission_sets        # ← Load role-based permissions
      register_extension_abilities    # ← Load custom registered abilities
    end
    
    # Class method: Register custom ability classes
    def self.register_ability(ability)
      abilities.add(ability)
    end
    
    # Class method: Remove custom ability classes
    def self.remove_ability(ability)
      abilities.delete(ability)
    end
    
    private
    
    # Load permission sets based on user's roles
    def activate_permission_sets
      Spree::Config.roles.activate_permissions! self, user
    end
    
    # Load any custom abilities registered via register_ability
    def register_extension_abilities
      Ability.abilities.each do |clazz|
        ability = clazz.send(:new, user)
        merge(ability)
      end
    end
  end
end
```

---

## Breaking Down Each Method

### **1. `initialize(current_user)`**

**When it's called:**
```ruby
# In BaseController
def current_ability
  Spree::Ability.new(current_api_user)  # ← Calls initialize
end
```

**What it does:**
```ruby
def initialize(current_user)
  @user = current_user || Spree.user_class.new  # Store user
  
  activate_permission_sets        # Load permissions from roles
  register_extension_abilities    # Load custom abilities
end
```

**Purpose:** Initialize the ability object with the current user and load all their permissions.

---

### **2. `activate_permission_sets`**

**What it does:**
```ruby
def activate_permission_sets
  # Calls Spree::Config.roles.activate_permissions! passing:
  # - self (the Ability object)
  # - user (the current user)
  Spree::Config.roles.activate_permissions! self, user
end
```

**Where `activate_permissions!` is defined:**
**File: `app/models/spree/core/role_configuration.rb`** ← NOW AT APPLICATION LEVEL!

```ruby
class RoleConfiguration
  # This is THE KEY METHOD that loads permissions for user's roles
  def activate_permissions!(ability, user)
    # Get all role names for user (including 'default')
    spree_roles = ['default'] | user.spree_roles.map(&:name)
    # => ["default", "customer"]
    
    # Collect all permission sets for these roles
    applicable_permissions = Set.new
    spree_roles.each do |role_name|
      applicable_permissions |= roles[role_name].permission_sets
    end
    # => Set[Spree::PermissionSets::DefaultCustomer]
    
    # Activate each permission set
    applicable_permissions.each do |permission_set|
      permission_set.new(ability).activate!  # ← Calls DefaultCustomer#activate!
    end
  end
end
```

**The flow:**
```
activate_permission_sets (in Ability)
  ↓
Spree::Config.roles.activate_permissions! self, user
  ↓
RoleConfiguration#activate_permissions! ← DEFINED HERE!
  ↓
Get user's roles: ['default'] | user.spree_roles.map(&:name)
  ↓
For each role the user has (e.g., "customer"):
  ↓
Get permission sets for that role (e.g., DefaultCustomer)
  ↓
For each permission set:
  permission_set = DefaultCustomer.new(ability)
  permission_set.activate!  # ← Calls can/cannot statements
```

**Example from our app:**

```ruby
# config/initializers/spree.rb line 32
config.roles.assign_permissions :customer, ['Spree::PermissionSets::DefaultCustomer']

# When activate_permission_sets runs for a customer user:
# 1. RoleConfiguration#activate_permissions! gets user's roles
# 2. Finds permission sets for 'customer' role: [DefaultCustomer]
# 3. Instantiates DefaultCustomer.new(ability)
# 4. Calls activate! which adds permissions:
#    can :create, Order
#    can [:show, :update], Order do |order, token|
#      order.user == user
#    end
```

**Purpose:** Load all permissions defined in the user's role's permission sets.

---

### **3. `register_extension_abilities` and `register_ability`**

**What they do:**

```ruby
# Class method - called in initializers or extensions
def self.register_ability(ability)
  abilities.add(ability)  # Add to the Set
end

# Instance method - called during initialize
def register_extension_abilities
  Ability.abilities.each do |clazz|
    ability = clazz.send(:new, user)
    merge(ability)  # Merge this ability's permissions into main ability
  end
end
```

**When to use:**
This is the **OLD WAY** (before permission sets) to add custom permissions. It's kept for backward compatibility.

**Example (NOT used in our app, but here's how it would work):**

```ruby
# app/models/custom_ability.rb
class CustomAbility
  include CanCan::Ability
  
  def initialize(user)
    can :manage, CustomResource if user.special?
  end
end

# config/initializers/custom_permissions.rb
Spree::Ability.register_ability(CustomAbility)
```

**Modern way:** Use permission sets instead (like we did with DefaultCustomer).

**Purpose:** Legacy mechanism for adding custom permissions. **Use permission sets instead.**

---

### **4. `remove_ability`**

**What it does:**
```ruby
def self.remove_ability(ability)
  abilities.delete(ability)
end
```

**When to use:**
Remove a previously registered custom ability.

**Example:**
```ruby
Spree::Ability.remove_ability(CustomAbility)
```

**Purpose:** Remove legacy custom abilities. Rarely used.

---

## RoleConfiguration - The Permission Mapper

**File: `app/models/spree/core/role_configuration.rb`** ← NOW AT APPLICATION LEVEL!

This is where `activate_permissions!` is actually defined. It's the bridge between roles and permission sets.

### **What It Does**

`RoleConfiguration` maintains a mapping of role names to permission sets:

```ruby
roles = {
  "default"  => Role(name: "default", permission_sets: [DefaultCustomer]),
  "admin"    => Role(name: "admin", permission_sets: [SuperUser]),
  "customer" => Role(name: "customer", permission_sets: [DefaultCustomer])
}
```

### **Key Methods**

#### **1. `assign_permissions(role_name, permission_sets)`**

Called in `config/initializers/spree.rb` to map roles to permission sets:

```ruby
# config/initializers/spree.rb
Spree.config do |config|
  config.roles.assign_permissions :customer, ['Spree::PermissionSets::DefaultCustomer']
end

# Internally stores:
# roles["customer"].permission_sets = [Spree::PermissionSets::DefaultCustomer]
```

#### **2. `activate_permissions!(ability, user)` ← THE KEY METHOD**

This is called by `Spree::Ability#activate_permission_sets` and does the actual work:

```ruby
def activate_permissions!(ability, user)
  # Step 1: Get all role names (always includes 'default')
  spree_roles = ['default'] | user.spree_roles.map(&:name)
  # Example: ["default", "customer"]
  
  # Step 2: Collect permission sets for all roles
  applicable_permissions = Set.new
  spree_roles.each do |role_name|
    applicable_permissions |= roles[role_name].permission_sets
  end
  # Example: Set[Spree::PermissionSets::DefaultCustomer]
  
  # Step 3: Activate each permission set
  applicable_permissions.each do |permission_set|
    permission_set.new(ability).activate!
  end
end
```

### **Why It's at Application Level**

Now that `RoleConfiguration` is at `app/models/spree/core/role_configuration.rb`, you can:

1. **Add debugging:**
```ruby
def activate_permissions!(ability, user)
  spree_roles = ['default'] | user.spree_roles.map(&:name)
  Rails.logger.debug("User #{user.email} has roles: #{spree_roles}")
  
  applicable_permissions = Set.new
  spree_roles.each do |role_name|
    sets = roles[role_name].permission_sets
    Rails.logger.debug("Role '#{role_name}' → #{sets.to_a}")
    applicable_permissions |= sets
  end
  
  applicable_permissions.each do |permission_set|
    Rails.logger.debug("Activating: #{permission_set}")
    permission_set.new(ability).activate!
  end
end
```

2. **Add custom logic:**
```ruby
def activate_permissions!(ability, user)
  # Skip default role for admin users
  spree_roles = user.has_spree_role?(:admin) ? 
                user.spree_roles.map(&:name) : 
                ['default'] | user.spree_roles.map(&:name)
  
  # ... rest of method
end
```

3. **Add caching:**
```ruby
def activate_permissions!(ability, user)
  cache_key = "permissions:#{user.id}:#{user.spree_roles.pluck(:id).sort.join(',')}"
  
  applicable_permissions = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    spree_roles = ['default'] | user.spree_roles.map(&:name)
    applicable_permissions = Set.new
    spree_roles.each do |role_name|
      applicable_permissions |= roles[role_name].permission_sets
    end
    applicable_permissions.to_a
  end
  
  applicable_permissions.each do |permission_set|
    permission_set.new(ability).activate!
  end
end
```

### **The Inner Role Class**

`RoleConfiguration` contains an inner `Role` class that holds the role-to-permission-sets mapping:

```ruby
class Role
  attr_reader :name, :permission_sets
  
  def initialize(name, permission_sets)
    @name = name
    @permission_sets = Spree::Core::ClassConstantizer::Set.new
    @permission_sets.concat permission_sets
  end
end
```

This is just a data structure to store:
- Role name (e.g., "customer")
- Permission sets for that role (e.g., [DefaultCustomer])

---

## Complete Authorization Flow

### **Step-by-Step: From Request to Permission Check**

```
1. User makes request
   POST /api/orders/R123456/line_items
   ↓

2. before_action :load_user runs
   @current_api_user = User.find_by(spree_api_key: cookie_value)
   Result: @current_api_user = #<User id: 5, email: "user@example.com">
   ↓

3. load_order runs
   authorize! :update, @order
   ↓

4. authorize! calls current_ability
   def current_ability
     Spree::Ability.new(current_api_user)  ←─────┐
   end                                            │
   ↓                                              │
                                                  │
5. Spree::Ability.initialize runs ◄──────────────┘
   def initialize(current_user)
     @user = current_user  # User #5
     activate_permission_sets  ←─────────────────┐
     register_extension_abilities                │
   end                                           │
   ↓                                             │
                                                 │
6. activate_permission_sets runs ◄───────────────┘
   Spree::Config.roles.activate_permissions! self, user
   ↓
   User has role "customer"
   ↓
   Load permission sets for "customer" role:
   - Spree::PermissionSets::DefaultCustomer
   ↓

7. DefaultCustomer.new(ability).activate! runs
   can :create, Order
   can [:show, :update], Order do |order, token|
     order.user == user  # Check if order belongs to user
   end
   ↓

8. Back to authorize!
   ability.can?(:update, @order)
   ↓
   Checks: Does order.user == current_user?
   ↓
   If YES → Continue
   If NO  → Raise CanCan::AccessDenied
```

---

## Visual Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Controller calls: authorize! :update, @order                    │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ CanCan calls: current_ability                                   │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ BaseController: Spree::Ability.new(current_api_user)            │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│ Spree::Ability#initialize                                       │
│   @user = current_api_user                                      │
│   activate_permission_sets ────┐                                │
│   register_extension_abilities  │                               │
└─────────────────────────────────┼───────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────┐
│ activate_permission_sets                                        │
│   Spree::Config.roles.activate_permissions! ────┐               │
└─────────────────────────────────────────────────┼───────────────┘
                                                  ↓
┌─────────────────────────────────────────────────────────────────┐
│ RoleConfiguration#activate_permissions! ← AT APP LEVEL!         │
│   spree_roles = ['default'] | user.spree_roles.map(&:name)     │
│   # => ["default", "customer"]                                  │
│                                                                 │
│   For each role, collect permission sets:                       │
│   applicable_permissions |= roles[role_name].permission_sets    │
│   # => Set[DefaultCustomer]                                     │
│                                                                 │
│   For each permission set:                      ────┐           │
│   permission_set = DefaultCustomer.new(ability)     │           │
│   permission_set.activate!                          │           │
└─────────────────────────────────────────────────────┼───────────┘
                                                      ↓
┌─────────────────────────────────────────────────────────────────┐
│ DefaultCustomer#activate!                                       │
│   can :create, Order                                            │
│   can [:show, :update], Order do |order, token|                 │
│     order.user == user                                          │
│   end                                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Two Ways to Add Permissions

### **Method 1: Permission Sets (MODERN - RECOMMENDED)**

**Used by:** Our customer role

**How:**
1. Create permission set class inheriting from `PermissionSets::Base`
2. Define `activate!` method with can/cannot statements
3. Register in `config/initializers/spree.rb`

**Example:**
```ruby
# app/models/spree/permission_sets/default_customer.rb
class DefaultCustomer < PermissionSets::Base
  def activate!
    can :create, Order
    can [:show, :update], Order do |order, token|
      order.user == user
    end
  end
end

# config/initializers/spree.rb
config.roles.assign_permissions :customer, ['Spree::PermissionSets::DefaultCustomer']
```

**Loaded by:** `activate_permission_sets` method

---

### **Method 2: Register Ability (LEGACY - OLD WAY)**

**Used by:** Extensions/plugins (before permission sets existed)

**How:**
1. Create ability class including `CanCan::Ability`
2. Register with `Spree::Ability.register_ability`

**Example:**
```ruby
# app/models/custom_ability.rb
class CustomAbility
  include CanCan::Ability
  
  def initialize(user)
    can :manage, CustomResource if user.admin?
  end
end

# config/initializers/custom_permissions.rb
Spree::Ability.register_ability(CustomAbility)
```

**Loaded by:** `register_extension_abilities` method

**Why it exists:** Backward compatibility. **Use permission sets instead!**

---

## Key Concepts Summary

| Concept | What It Is | Purpose |
|---------|-----------|---------|
| `Spree::Ability` | Central authorization class | Loads all permissions for a user |
| `initialize(user)` | Constructor | Stores user and loads all permissions |
| `activate_permission_sets` | Instance method | Calls RoleConfiguration to load permissions |
| `RoleConfiguration` | Permission mapper class ← AT APP LEVEL! | Maps roles to permission sets |
| `RoleConfiguration#activate_permissions!` | The key method | Loads permission sets for user's roles |
| `RoleConfiguration#assign_permissions` | Configuration method | Maps role name to permission sets |
| `register_extension_abilities` | Instance method | Loads custom registered abilities (LEGACY) |
| `register_ability(ability)` | Class method | Add custom ability class (LEGACY) |
| `remove_ability(ability)` | Class method | Remove custom ability class (LEGACY) |
| `@user` | Instance variable | The current user |
| `abilities` | Class variable (Set) | Stores registered custom ability classes |

---

## Real Example from Our App

```ruby
# 1. User with customer role makes request
user = User.find(5)
user.spree_roles # => [#<Role name: "customer">]

# 2. Controller calls current_ability
ability = Spree::Ability.new(user)

# 3. initialize runs
#    @user = user (User #5)
#    activate_permission_sets  # ← This runs
#    register_extension_abilities  # ← This runs but abilities Set is empty

# 4. activate_permission_sets loads DefaultCustomer
#    - Finds user has "customer" role
#    - Looks up permission sets: ['Spree::PermissionSets::DefaultCustomer']
#    - Calls: DefaultCustomer.new(ability).activate!

# 5. DefaultCustomer#activate! adds permissions
#    can :create, Order
#    can [:show, :update], Order do |order, token|
#      order.user == @user  # User #5
#    end

# 6. Now ability object has all permissions loaded!
ability.can?(:update, some_order)  # Checks against loaded permissions
```

---

## Quick Reference

```ruby
# How permissions are loaded
Spree::Ability.new(user)
  ↓
initialize(user)
  ↓
  ├─ activate_permission_sets (MODERN)
  │    ↓
  │  Loads role-based permission sets
  │  (DefaultCustomer, SuperUser, etc.)
  │
  └─ register_extension_abilities (LEGACY)
       ↓
     Loads custom registered abilities
     (Usually empty in modern apps)

# How to add permissions TODAY
1. Create permission set class
2. Add to config/initializers/spree.rb
3. Assign to role

# How permissions were added BEFORE (don't do this)
1. Create ability class
2. Call Spree::Ability.register_ability(MyAbility)
```

---

**Bottom Line:** 

- **`Spree::Ability`** = The glue between CanCan and Spree's role system
- **`activate_permission_sets`** = Loads permissions from your role configuration (MODERN WAY)
- **`register_extension_abilities`** = Loads old-style custom abilities (LEGACY - ignore unless using old extensions)
- **Most apps:** Only use `activate_permission_sets` with permission sets

