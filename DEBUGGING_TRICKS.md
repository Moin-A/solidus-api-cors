# Debugging Tricks for Rails/Solidus Development

A collection of debugging techniques and tricks for troubleshooting Rails applications, especially when dealing with complex frameworks like Solidus.

---

## Table of Contents
1. [Exception Handling & Stack Traces](#exception-handling--stack-traces)
2. [Validation Bypassing](#validation-bypassing)
3. [Call Stack Analysis](#call-stack-analysis)
4. [State Machine Debugging](#state-machine-debugging)
5. [ActiveRecord Debugging](#activerecord-debugging)
6. [Common Patterns](#common-patterns)

---

## Exception Handling & Stack Traces

### Catching Specific Exceptions

Use specific exception types to catch and inspect errors:

```ruby
begin
  order.save
rescue TypeError => e
  puts "TypeError detected:"
  puts e.message
  puts e.backtrace.first(20)  # First 20 lines of stack trace
  raise  # Re-raise to see full error
rescue SystemStackError => e
  puts "SystemStackError (infinite recursion) detected:"
  puts "Message: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(30)
  raise
rescue StandardError => e
  puts "Error: #{e.class.name}"
  puts e.message
  puts e.backtrace.first(10)
  raise
end
```

### Common Exception Types

| Exception | When It Occurs | Use Case |
|-----------|----------------|----------|
| `TypeError` | Wrong type passed (e.g., `nil` where `String` expected) | Type mismatches |
| `SystemStackError` | Infinite recursion (stack overflow) | Callback loops, circular dependencies |
| `NoMethodError` | Method doesn't exist on object | Missing methods, nil objects |
| `ArgumentError` | Wrong number/type of arguments | Method signature issues |
| `ActiveRecord::RecordInvalid` | Validation failed | Model validation issues |

### Stack Trace Analysis

**Stack traces are in DESCENDING order** (most recent call at top):

```
Error: SystemStackError (stack level too deep)

app/models/spree/order_update_attributes.rb:24:in `call'        ← Most recent (where error occurred)
app/models/spree/order_updater.rb:180:in `persist_totals'      ← Called by above
app/models/spree/order_updater.rb:30:in `recalculate'          ← Called by above
app/models/spree/order.rb:204:in `update_order'                ← Called by above
...
```

**Reading strategy:**
1. Start at the top (where error occurred)
2. Work down to find the root cause
3. Look for patterns (same method appearing multiple times = recursion)

---

## Validation Bypassing

### Using `save(validate: false)` to Test Hypotheses

When debugging, you can bypass validation to isolate the problem:

```ruby
# Hypothesis: "Is validation causing the issue?"
begin
  order.save(validate: false)  # Skip validation
  puts "Save succeeded without validation - validation might be the issue"
rescue => e
  puts "Save failed even without validation - issue is elsewhere"
  puts e.class.name
  puts e.message
end
```

### When to Use `validate: false`

✅ **Good for:**
- Testing if validation is causing recursion
- Isolating callback vs validation issues
- Debugging state machine transitions
- Testing if database constraints are the problem

❌ **Avoid in production:**
- Never use `validate: false` in production code without good reason
- Always validate user input
- Use only for debugging or internal operations

### Example: Debugging Recursion

```ruby
# Before fix - causes recursion
def persist_totals
  order.save!  # Triggers validation → callbacks → recalculate → persist_totals → recursion!
end

# After fix - breaks recursion
def persist_totals
  order.save!(validate: false)  # Skips validation, breaks the loop
end
```

### Other Validation Bypass Methods

```ruby
# Skip validation
order.save(validate: false)
order.save!(validate: false)

# Skip callbacks (more dangerous)
order.save(validate: false, touch: false)
order.update_columns(attribute: value)  # Bypasses everything, no callbacks

# Skip specific validations
order.save(context: :skip_custom_validation)
```

---

## Call Stack Analysis

### Inspecting Call Stack

```ruby
def some_method
  puts "Current method: #{__method__}"
  puts "Caller: #{caller.first(5).join("\n")}"
  
  # Full backtrace
  puts caller
end
```

### Finding Recursion Patterns

```ruby
def detect_recursion
  @call_count ||= {}
  method_name = __method__
  @call_count[method_name] = (@call_count[method_name] || 0) + 1
  
  if @call_count[method_name] > 10
    raise "Possible infinite recursion in #{method_name}"
  end
  
  # Your code here
ensure
  @call_count[method_name] = (@call_count[method_name] || 0) - 1
end
```

### Debugging Callback Chains

```ruby
# In your model
before_save :debug_before_save
after_save :debug_after_save

def debug_before_save
  puts "=== BEFORE SAVE ==="
  puts "State: #{state}"
  puts "Changed: #{changed_attributes.keys}"
  puts "Caller: #{caller.first(3).join("\n")}"
end

def debug_after_save
  puts "=== AFTER SAVE ==="
  puts "State: #{state}"
  puts "Caller: #{caller.first(3).join("\n")}"
end
```

---

## State Machine Debugging

### Debugging State Transitions

```ruby
# Add to state machine definition
state_machine :state do
  after_transition do |order, transition|
    puts "Transition: #{transition.from} → #{transition.to}"
    puts "Event: #{transition.event}"
    puts "Order ID: #{order.id}"
    
    # Check if we're in a save operation
    if order.instance_variable_get(:@_already_saving)
      puts "WARNING: Already in save operation - possible recursion!"
    end
  end
end
```

### Testing State Machine Hypotheses

```ruby
# Hypothesis: "Is state machine validation causing the issue?"
order.state = 'payment'  # Set state directly
order.save(validate: false)  # Skip validation

if order.persisted?
  puts "State change works without validation - state machine validation is the issue"
end
```

### Finding Invalid Transitions

```ruby
# Check available transitions
order.state_events  # => [:next, :cancel, ...]

# Check if transition is valid
order.can_next?  # => true/false

# See why transition failed
order.next  # Returns false if invalid
order.errors.full_messages  # => ["Reason why it failed"]
```

---

## ActiveRecord Debugging

### Inspecting Model State

```ruby
# Check what changed
order.changed?  # => true/false
order.changed  # => ["state", "total"]
order.changes  # => {"state" => ["cart", "address"], "total" => [0, 100]}

# Check if persisted
order.persisted?  # => true/false
order.new_record?  # => true/false

# Check associations
order.payments.loaded?  # => true if already loaded
order.payments.size  # => Forces load if not loaded
```

### Debugging Associations

```ruby
# Check if association is loaded
order.association(:payments).loaded?  # => true/false

# Force reload
order.payments.reload

# Check association cache
order.association(:payments).target  # => Cached array
```

### SQL Query Debugging

```ruby
# Enable SQL logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# See generated SQL
order.payments.to_sql  # => "SELECT ..."

# Count queries
ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "SQL: #{event.payload[:sql]}"
end
```

---

## Common Patterns

### Pattern 1: Debugging Infinite Recursion

```ruby
def problematic_method
  begin
    order.save  # Might cause recursion
  rescue SystemStackError => e
    puts "=== RECURSION DETECTED ==="
    puts "Backtrace:"
    puts e.backtrace.first(20)
    
    # Test hypothesis: Is validation causing it?
    order.save(validate: false)
    puts "Save with validate: false succeeded - validation is the issue"
    
    raise
  end
end
```

### Pattern 2: Isolating Callback Issues

```ruby
# Test if callbacks are the problem
order.save(validate: false)  # Skips validation but runs callbacks

# Test if validation is the problem
order.valid?  # Just validates, doesn't save

# Test if database is the problem
order.update_columns(state: 'payment')  # Direct DB update, no callbacks/validation
```

### Pattern 3: Debugging State Machine Validation

```ruby
# Check state machine validation separately
order.valid?  # Runs all validations including state machine

# Check state machine transitions
order.state_machine(:state).events_for_current_state  # => Available events

# Manually trigger transition to see what happens
begin
  order.next!
rescue StateMachines::InvalidTransition => e
  puts "Transition failed: #{e.message}"
  puts "Available events: #{order.state_events}"
end
```

### Pattern 4: Conditional Debugging

```ruby
# Only debug in development
if Rails.env.development?
  puts "Debug info: #{order.inspect}"
end

# Debug flag
DEBUG = true
puts "Debug: #{order.state}" if DEBUG

# Use logger
Rails.logger.debug "Order state: #{order.state}"
```

### Pattern 5: Time-Travel Debugging

```ruby
# Check state before and after
before_state = order.state
before_total = order.total

order.save

after_state = order.state
after_total = order.total

if before_state != after_state
  puts "State changed: #{before_state} → #{after_state}"
end

if before_total != after_total
  puts "Total changed: #{before_total} → #{after_total}"
end
```

---

## Quick Reference

### Exception Handling Cheat Sheet

```ruby
begin
  # Your code
rescue TypeError => e
  puts e.backtrace.first(20)
rescue SystemStackError => e
  puts "Recursion: #{e.backtrace.first(10)}"
rescue => e
  puts "#{e.class}: #{e.message}"
ensure
  # Cleanup
end
```

### Validation Bypass Cheat Sheet

```ruby
order.save(validate: false)           # Skip validation
order.save!(validate: false)          # Skip validation, raise on error
order.update_columns(attr: value)     # Skip everything (callbacks + validation)
order.update_column(:attr, value)      # Skip everything, single attribute
```

### Debugging Checklist

- [ ] Check stack trace (read top to bottom)
- [ ] Use `validate: false` to test hypothesis
- [ ] Check for recursion patterns in stack trace
- [ ] Inspect model state (`changed?`, `persisted?`)
- [ ] Check callbacks (`before_save`, `after_save`)
- [ ] Verify state machine transitions (`can_next?`, `state_events`)
- [ ] Check associations (loaded?, reload)
- [ ] Use conditional debugging (development only)

---

**Created:** January 2025  
**Topic:** Debugging Techniques for Rails/Solidus  
**Related Files:** `STATE_MACHINE_GUIDE.md`, `RAILS_CALLBACKS_AND_LIFECYCLE_QA.md`

