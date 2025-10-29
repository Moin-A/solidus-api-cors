# Solidus State Machine Guide - Order Checkout Flow

A comprehensive guide to understanding how Solidus uses state machines to manage the order checkout process.

---

## Table of Contents
1. [What is a State Machine?](#what-is-a-state-machine)
2. [Order States and Transitions](#order-states-and-transitions)
3. [How State Machine is Implemented](#implementation)
4. [Dynamic Method Generation](#dynamic-method-generation)
5. [Callbacks and Guards](#callbacks-and-guards)
6. [Practical Examples](#practical-examples)
7. [Debugging State Transitions](#debugging)

---

## What is a State Machine?

A **state machine** is a pattern where an object can be in one of several **states** and can **transition** between states based on **events**.

### Real-World Example: Order Checkout

```
Cart State → Address State → Delivery State → Payment State → Complete State
    ↓            ↓              ↓                ↓               ↓
  Shopping   Add Address   Choose Shipping   Add Payment    Order Done
```

### Key Concepts

| Concept | Description | Example |
|---------|-------------|---------|
| **State** | Current status | `order.state = "address"` |
| **Event** | Action that causes transition | `order.next!` |
| **Transition** | Moving from one state to another | `address → delivery` |
| **Guard** | Condition that must be true | `ensure_shipping_address` |
| **Callback** | Code run before/after transition | `create_proposed_shipments` |

---

## Order States and Transitions

### Default Solidus States

```ruby
# Order lifecycle
cart → address → delivery → payment → confirm → complete
```

### State Definitions

```ruby
# From: app/models/spree/core/state_machines/order/class_methods.rb

state_machine :state, initial: :cart do
  event :next do
    transition from: :cart,     to: :address
    transition from: :address,  to: :delivery
    transition from: :delivery, to: :payment
    transition from: :payment,  to: :confirm
    transition from: :confirm,  to: :complete
  end
end
```

### Visual State Flow

```
┌──────────────────────────────────────────────────────────────┐
│ CART STATE                                                    │
│ - Add products                                                │
│ - Modify quantities                                           │
└─────────────────────┬────────────────────────────────────────┘
                      │ next!
                      ↓
┌──────────────────────────────────────────────────────────────┐
│ ADDRESS STATE                                                 │
│ - Set bill_address                                            │
│ - Set ship_address                                            │
│ Guards:                                                       │
│   ✓ ensure_shipping_address                                  │
└─────────────────────┬────────────────────────────────────────┘
                      │ next!
                      ↓
┌──────────────────────────────────────────────────────────────┐
│ DELIVERY STATE                                                │
│ - Choose shipping method                                      │
│ - Calculate shipping rates                                    │
│ Callbacks:                                                    │
│   → create_proposed_shipments                                 │
│   → ensure_available_shipping_rates                           │
└─────────────────────┬────────────────────────────────────────┘
                      │ next!
                      ↓
┌──────────────────────────────────────────────────────────────┐
│ PAYMENT STATE                                                 │
│ - Add payment method                                          │
│ - Authorize payment                                           │
└─────────────────────┬────────────────────────────────────────┘
                      │ next!
                      ↓
┌──────────────────────────────────────────────────────────────┐
│ CONFIRM STATE (optional)                                      │
│ - Review order                                                │
│ - Final confirmation                                          │
└─────────────────────┬────────────────────────────────────────┘
                      │ next! (or complete!)
                      ↓
┌──────────────────────────────────────────────────────────────┐
│ COMPLETE STATE                                                │
│ - Order placed                                                │
│ - Inventory allocated                                         │
│ - Emails sent                                                 │
└──────────────────────────────────────────────────────────────┘
```

---

## Implementation

### File Structure

```
app/models/spree/
├── order.rb                                    # Includes state machine
└── core/
    └── state_machines/
        └── order/
            └── class_methods.rb                # State machine definition
```

### How It's Loaded

**File:** `app/models/spree/order.rb`

```ruby
class Spree::Order < Spree::Base
  # Line 38-40
  include ::Spree::Config.state_machines.order  # ← Loads state machine
  
  # state_machines.order resolves to:
  # Spree::Core::StateMachines::Order::ClassMethods
end
```

**Configuration:** `app/models/spree/app_configuration.rb`

```ruby
class Spree::AppConfiguration
  # Line 690-695
  class_name_attribute :state_machines, default: {
    order: 'Spree::Core::StateMachines::Order::ClassMethods',
    # ... other state machines
  }
end
```

### State Machine Definition

**File:** `app/models/spree/core/state_machines/order/class_methods.rb`

```ruby
module Spree::Core::StateMachines::Order::ClassMethods
  extend ActiveSupport::Concern

  included do
    # This is where the magic happens
    checkout_flow(&Spree::Config.checkout_flow)
  end
end
```

---

## Dynamic Method Generation

### The `checkout_flow` Method

**Location:** Lines 33-75 in `class_methods.rb`

```ruby
def checkout_flow(&block)
  if block
    @checkout_flow = block  # Store the block
  end
  
  # Always evaluate and rebuild
  instance_eval(&@checkout_flow) if @checkout_flow
end
```

### The `go_to_state` Method

This is the **core method** that defines states and transitions.

**Location:** Lines 77-143 in `class_methods.rb`

```ruby
def go_to_state(name, options = {}, &block)
  # 1. Register state
  states[name] = options
  
  # 2. Define state machine
  state_machine.state(name)
  
  # 3. Add transition
  state_machine.event(:next) do
    transition(to: name, from: previous_states)
  end
  
  # 4. Add callbacks from options
  options[:before].each do |callback|
    state_machine.before_transition(to: name, do: callback)
  end
  
  # 5. Execute block for additional config
  state_machine.before_transition(to: name) do |order|
    order.instance_eval(&block)
  end
end
```

### Example Usage

```ruby
# In Spree::Config.checkout_flow block
checkout_flow do
  go_to_state :address
  
  go_to_state :delivery,
    before: [:ensure_shipping_address, :create_proposed_shipments] do
    # Additional validation logic
    if shipments.empty?
      errors.add(:base, "No shipping methods available")
      false
    end
  end
  
  go_to_state :payment
  go_to_state :complete
end
```

### How `next!` Gets Created

The `next` event is dynamically created by the state machine:

```ruby
# state_machine gem automatically creates:
state_machine.event(:next) do
  transition from: :cart,     to: :address
  transition from: :address,  to: :delivery
  transition from: :delivery, to: :payment
  transition from: :payment,  to: :confirm
  transition from: :confirm,  to: :complete
end

# This generates methods:
order.next!         # Trigger event (raises on failure)
order.next          # Trigger event (returns false on failure)
order.can_next?     # Check if transition is possible
order.next_events   # List possible events
```

### Generated Methods

```ruby
# State checks
order.cart?         # => true if state == 'cart'
order.address?      # => true if state == 'address'
order.complete?     # => true if state == 'complete'

# State history
order.state_changes  # => Array of state changes

# Available transitions
order.state_paths   # => All possible transition paths
order.state_events  # => Events available in current state
```

---

## Callbacks and Guards

### Types of Callbacks

```ruby
before_transition to: :delivery do
  # Runs BEFORE entering delivery state
end

after_transition to: :delivery do
  # Runs AFTER entering delivery state
end

around_transition to: :delivery do |order, transition, block|
  # Runs AROUND the transition
  puts "Before"
  block.call
  puts "After"
end
```

### Address → Delivery Transition (Example)

**Code:** Lines 99-110 in `class_methods.rb`

```ruby
if states[:delivery]
  # Guard: Ensure address exists
  before_transition to: :delivery, do: :ensure_shipping_address
  
  # Callback: Create shipments
  before_transition to: :delivery, do: :create_proposed_shipments
  
  # Guard: Ensure shipping rates calculated
  before_transition to: :delivery, do: :ensure_available_shipping_rates
end
```

### Implementation Details

**Guard: `ensure_shipping_address`**

```ruby
# app/models/spree/order.rb (approx line 820)
def ensure_shipping_address
  unless ship_address&.valid?
    errors.add(:base, "Valid shipping address required")
    return false  # ← Prevents transition!
  end
  true
end
```

**Callback: `create_proposed_shipments`**

```ruby
# app/models/spree/order_shipping.rb
def create_proposed_shipments
  shipments.destroy_all
  
  coordinator = Spree::Config.stock.coordinator_class.new(self)
  self.shipments = coordinator.shipments
  
  true  # ← Must return true to continue
end
```

**Guard: `ensure_available_shipping_rates`**

```ruby
# app/models/spree/order.rb (line 834-840)
def ensure_available_shipping_rates
  if shipments.empty? || shipments.any? { |s| s.shipping_rates.blank? }
    errors.add(:base, "We are unable to calculate shipping rates")
    return false  # ← THIS is why your transition failed!
  end
  true
end
```

### Callback Execution Order

```
User calls: order.next!
  ↓
1. Check: Can transition? (from: address, to: delivery exists?)
  ↓ YES
2. Run: before_transition callbacks IN ORDER
  ↓
  2a. ensure_shipping_address
      ↓ Returns false? → ABORT!
      ↓ Returns true? → Continue
  ↓
  2b. create_proposed_shipments
      ↓ Returns false? → ABORT!
      ↓ Returns true? → Continue
  ↓
  2c. ensure_available_shipping_rates
      ↓ Returns false? → ABORT! ← YOUR PROBLEM WAS HERE
      ↓ Returns true? → Continue
  ↓
3. Update: state = 'delivery'
  ↓
4. Save: order.save!
  ↓
5. Run: after_transition callbacks
  ↓
6. Return: true (success!)
```

### What Happens on Failure

```ruby
order.next!  # If callback returns false:

# 1. Transition aborted
order.state  # => Still "address" (didn't change)

# 2. Errors added
order.errors.full_messages
# => ["We are unable to calculate shipping rates"]

# 3. Exception raised (for next!)
# StateMachines::InvalidTransition: 
#   Cannot transition state via :next from :address

# If you use next (without !):
order.next  # Returns false, no exception
```

---

## Practical Examples

### Example 1: Simple Transition

```ruby
order = Spree::Order.create!
order.state  # => "cart"

# Add a line item
order.line_items.create!(variant: variant, quantity: 1)

# Try to advance
order.next!  # cart → address
order.state  # => "address"
```

### Example 2: Failed Transition (No Address)

```ruby
order.state  # => "address"

# Try to advance without setting address
order.next!
# StateMachines::InvalidTransition: 
#   Cannot transition state via :next from :address
#   (Reason(s): Valid shipping address required)

order.errors.full_messages
# => ["Valid shipping address required"]
```

### Example 3: Successful Full Flow

```ruby
# 1. Start
order = Spree::Order.create!
order.line_items.create!(variant: variant, quantity: 1)

# 2. Address
order.next!  # cart → address
order.ship_address = Spree::Address.create!(address_params)
order.bill_address = order.ship_address
order.save!

# 3. Delivery
order.next!  # address → delivery
# Creates shipments, calculates rates

order.shipments.first.selected_shipping_rate_id = 
  order.shipments.first.shipping_rates.first.id
order.save!

# 4. Payment
order.next!  # delivery → payment
order.payments.create!(
  payment_method: payment_method,
  amount: order.total
)

# 5. Complete
order.next!  # payment → complete (may go through confirm)
order.state  # => "complete"
```

### Example 4: Checking Before Transition

```ruby
# Check if can transition
order.can_next?  # => true/false

# See why it can't
unless order.can_next?
  puts "Cannot advance because:"
  order.errors.full_messages.each { |msg| puts "  - #{msg}" }
end

# Get available events
order.state_events  # => [:next, :cancel, etc.]
```

### Example 5: Custom Transition

```ruby
# Go directly to a specific state (dangerous!)
order.state = 'complete'
order.save!  # Bypasses callbacks and guards!

# Better: Use events
order.complete!  # If complete event is defined
order.cancel!    # Cancel event
```

---

## Debugging State Transitions

### Enable Verbose Logging

```ruby
# In console or spec
order = Spree::Order.last

# See state machine definition
order.class.state_machines[:state].states.map(&:name)
# => [:cart, :address, :delivery, :payment, :confirm, :complete]

# See transitions
order.class.state_machines[:state].events[:next].branches.each do |branch|
  puts "#{branch.state_requirements.first[:from].values.first} → #{branch.state_requirements.first[:to]}"
end
```

### Debug Callback Execution

Add logging to see what's happening:

```ruby
# In app/models/spree/order.rb
def ensure_shipping_address
  Rails.logger.debug "=== ensure_shipping_address called ==="
  Rails.logger.debug "ship_address: #{ship_address.inspect}"
  Rails.logger.debug "valid?: #{ship_address&.valid?}"
  
  unless ship_address&.valid?
    Rails.logger.debug "FAILED: Invalid address"
    errors.add(:base, "Valid shipping address required")
    return false
  end
  
  Rails.logger.debug "PASSED: Address valid"
  true
end
```

### Trace the Transition

```ruby
# See what would happen without executing
order.state  # => "address"

# Manually run guards
order.ensure_shipping_address  # => true/false
order.create_proposed_shipments  # => true/false
order.ensure_available_shipping_rates  # => true/false

# If all return true, next! will succeed
```

### Check State Machine Configuration

```ruby
# In console
machine = Spree::Order.state_machines[:state]

# States
machine.states.map(&:name)

# Events
machine.events.keys

# Current state
order.state

# Can transition?
machine.events[:next].can_fire?(order)

# Transitions from current state
machine.events[:next].branches.select do |branch|
  branch.state_requirements.first[:from].matches?(order.state)
end
```

---

## Common Issues and Solutions

### Issue 1: Transition Not Happening

**Problem:**
```ruby
order.next!
# No error, but state didn't change
order.state  # => Still "address"
```

**Debug:**
```ruby
# Check if callback returned false silently
order.ensure_shipping_address  # Run manually
order.errors.full_messages  # Check for errors
```

**Solution:** Ensure all callbacks return `true`

---

### Issue 2: Can't Skip States

**Problem:**
```ruby
order.state = 'complete'  # Want to skip to complete
order.save!
# Works, but breaks things!
```

**Why:** Callbacks and validations are skipped

**Solution:** Use proper events or define custom transitions:

```ruby
# In state machine definition
event :skip_to_complete do
  transition from: [:cart, :address, :delivery, :payment], to: :complete
end

# Usage
order.skip_to_complete!
```

---

### Issue 3: Callbacks Running Multiple Times

**Problem:**
```ruby
# callback runs twice!
before_transition to: :delivery, do: :create_proposed_shipments
```

**Cause:** Called `next!` multiple times or state machine reloaded

**Solution:** Make callbacks idempotent:

```ruby
def create_proposed_shipments
  return true if shipments.any? && shipments.all?(&:pending?)
  
  shipments.destroy_all
  # ... create new shipments
  true
end
```

---

### Issue 4: Understanding Error Messages

```ruby
order.next!
# StateMachines::InvalidTransition: 
#   Cannot transition state via :next from :address
#   (Reason(s): We are unable to calculate shipping rates)
```

**Breaking it down:**
- **Event:** `next`
- **From state:** `address`
- **Failed callback:** One that added error "We are unable to calculate shipping rates"
- **Which callback?** `ensure_available_shipping_rates`

**Debug:**
```ruby
# Run the callback directly
order.ensure_available_shipping_rates
# => false

# Check why
order.shipments.any?  # => true/false?
order.shipments.first.shipping_rates.any?  # => true/false?
```

---

## Advanced Topics

### Custom States

You can define custom states for your business logic:

```ruby
# In an initializer
Spree::Config.checkout_flow = lambda do |checkout_flow|
  checkout_flow.go_to_state :cart
  checkout_flow.go_to_state :address
  checkout_flow.go_to_state :delivery
  checkout_flow.go_to_state :payment
  
  # Custom state!
  checkout_flow.go_to_state :age_verification,
    before: [:ensure_age_verified] do
    # Block runs on transition TO this state
    if line_items.any?(&:alcohol?)
      # Require age verification
      true
    else
      # Skip this state
      next!  # Advance immediately
      false  # Don't save
    end
  end
  
  checkout_flow.go_to_state :confirm
  checkout_flow.go_to_state :complete
end
```

### Conditional Transitions

```ruby
# Skip confirm state if total < 100
before_transition to: :confirm do |order|
  if order.total < 100
    order.state = 'complete'  # Skip confirm
    false  # Don't enter confirm
  else
    true  # Enter confirm
  end
end
```

### State-Specific Scopes

```ruby
# In app/models/spree/order.rb
scope :in_checkout, -> { where.not(state: ['cart', 'complete']) }
scope :completed, -> { where(state: 'complete') }
scope :incomplete, -> { where.not(state: 'complete') }

# Usage
Spree::Order.in_checkout.count
Spree::Order.completed.where('created_at > ?', 1.day.ago)
```

---

## State Machine Gem Methods

Solidus uses the `state_machines-activerecord` gem. Key methods:

### Instance Methods

```ruby
# State checks
order.cart?
order.address?
order.state_name  # => :address

# Events
order.next!        # Fire event (raise on failure)
order.next         # Fire event (return false on failure)
order.can_next?    # Check if can fire

# Transitions
order.fire_events(:next)  # Manually fire
order.state_events        # List available events
order.state_transitions   # History of transitions
```

### Class Methods

```ruby
# State machine
Spree::Order.state_machines
Spree::Order.state_machines[:state]

# States
Spree::Order.state_machines[:state].states

# Events  
Spree::Order.state_machines[:state].events
```

---

## Testing State Transitions

### RSpec Examples

```ruby
# spec/models/spree/order_spec.rb
RSpec.describe Spree::Order do
  describe "state transitions" do
    let(:order) { create(:order) }
    
    it "transitions from cart to address" do
      expect { order.next! }.to change(order, :state)
        .from("cart").to("address")
    end
    
    it "requires address before delivery" do
      order.update!(state: 'address')
      
      expect { order.next! }.to raise_error(StateMachines::InvalidTransition)
      expect(order.errors.full_messages).to include("Valid shipping address required")
    end
    
    it "creates shipments on delivery transition" do
      order.update!(state: 'address')
      order.ship_address = create(:address)
      order.save!
      
      expect { order.next! }.to change(order.shipments, :count).by(1)
    end
  end
end
```

---

## Quick Reference

### Common State Transitions

| From | Event | To | Key Callbacks |
|------|-------|-----|--------------|
| cart | next! | address | - |
| address | next! | delivery | ensure_shipping_address, create_proposed_shipments |
| delivery | next! | payment | ensure_available_shipping_rates |
| payment | next! | confirm/complete | process_payments |
| confirm | next!/complete! | complete | finalize |

### Key Files

| File | Purpose |
|------|---------|
| `app/models/spree/order.rb` | Main order model |
| `app/models/spree/core/state_machines/order/class_methods.rb` | State machine definition |
| `app/models/spree/order_shipping.rb` | Shipping-related callbacks |
| `app/models/spree/app_configuration.rb` | State machine configuration |

### Useful Console Commands

```ruby
# Current state
order.state

# Can advance?
order.can_next?

# Advance
order.next!  # Raises on failure
order.next   # Returns false on failure

# Why can't advance?
order.errors.full_messages

# See transitions
order.state_changes

# Available events
order.state_events
```

---

**Created:** October 26, 2025  
**Topic:** Solidus State Machine & Order Checkout Flow  
**Related Files:** `SHIPPING_CONFIGURATION_GUIDE.md`, `RAILS_CALLBACKS_AND_LIFECYCLE_QA.md`



