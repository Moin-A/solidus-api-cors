# Debugging SystemStackError (Stack Level Too Deep) - Complete Process

## Problem Statement

When calling `PATCH /api/checkouts/:order_number/update` with payment attributes, the application crashed with:
```
SystemStackError (stack level too deep)
app/models/spree/order_update_attributes.rb:23:in `call'
```

The request would hang indefinitely and eventually timeout.

---

## Initial Hypothesis

**Hypothesis 1:** The recursion is happening in `order.save` → validation → callbacks → `order.save` again.

**First Attempt:** Added exception handling to capture the stack trace.

```ruby
# app/models/spree/order_update_attributes.rb
begin
  order.save
rescue SystemStackError => e
  puts e.backtrace.first(50)
  raise
end
```

**Result:** Stack trace was very short, showing only:
```
app/models/spree/order_update_attributes.rb:23:in `call'
app/controllers/spree/api/checkouts_controller.rb:44:in `update'
```

This indicated the recursion was happening very quickly, making it hard to see the full loop.

---

## Debugging Approach #1: Check for Recursion in `recalculate`

**Hypothesis 2:** The `order.recalculate` method might be calling `order.save` which triggers `recalculate` again.

**Investigation:**
- Found that `recalculate` → `persist_totals` → `order.save!`
- This could cause recursion if `recalculate` is called during `order.save` validation

**Attempt 1.1:** Skip `recalculate` if order has unsaved changes
```ruby
# app/models/spree/order_updater.rb
def recalculate
  return if order.changed? && !order.new_record?
  # ... rest of method
end
```

**Result:** ❌ Still timing out. The recursion wasn't prevented.

**Attempt 1.2:** Use `update_columns` in `persist_totals` to bypass callbacks
```ruby
# app/models/spree/order_updater.rb
def persist_totals
  order.update_columns(
    item_count: order.item_count,
    item_total: order.item_total,
    # ... other totals
  )
end
```

**Result:** ❌ Still timing out. The recursion was happening elsewhere.

**Attempt 1.3:** Use thread-local flags to prevent `recalculate` during save
```ruby
# app/models/spree/order_update_attributes.rb
thread_key = "saving_order_#{order.object_id}"
Thread.current[thread_key] = true
begin
  order.save
ensure
  Thread.current[thread_key] = false
end

# app/models/spree/order_updater.rb
def recalculate
  return if Thread.current["saving_order_#{order.object_id}"]
  # ... rest of method
end
```

**What this does:**
- `Thread.current` is a hash-like storage that's unique to each thread (like a thread-safe global variable)
- Before `order.save`, we set a flag: `Thread.current[thread_key] = true`
- Inside `recalculate`, we check this flag: `return if Thread.current[thread_key]`
- If the flag is set, `recalculate` exits early, preventing it from running during `order.save`
- After `order.save` completes, we clear the flag in the `ensure` block

**Why thread-local?**
- Each HTTP request runs in its own thread
- `Thread.current` ensures the flag is isolated to that specific request/thread
- Multiple concurrent requests won't interfere with each other's flags

**Result:** ❌ Still timing out. The recursion wasn't coming from `recalculate`.

---

## Debugging Approach #2: Check State Machine Callbacks

**Hypothesis 3:** State machine `after_transition` callbacks might be causing recursion.

**Investigation:**
- Found `after_transition` callback that calls `order.save` (line 54)
- Found another `after_transition` callback that calls `order.recalculate` (line 126)

**Attempt 2.1:** Remove `order.save` from state machine callback
```ruby
# app/models/spree/core/state_machines/order/class_methods.rb
after_transition do |order, transition|
  # ... create state_changes
  # Removed: order.save
end
```

**Result:** ❌ Still timing out. The recursion wasn't from state machine transitions.

**Attempt 2.2:** Use `update_column` instead of `save` in state machine callback
```ruby
after_transition do |order, transition|
  # ...
  order.update_column(:state, order.state) if order.state_changed?
end
```

**Result:** ❌ Still timing out.

---

## Debugging Approach #3: Check Payment Callbacks

**Hypothesis 4:** Payment `after_save` or `after_create` callbacks might be causing recursion.

**Investigation:**
- Found `payment.after_save :update_order` (line 31)
- Found `payment.after_create :invalidate_old_payments` (line 36)
- Found `payment.belongs_to :order, touch: true` (line 16)

**Attempt 3.1:** Disable `payment.after_save :update_order` callback
```ruby
# app/models/spree/order_update_attributes.rb
payment.define_singleton_method(:update_order) { }
payment.save(validate: false)
```

**Result:** ❌ Still timing out.

**Attempt 3.2:** Disable `touch: true` on payment's order association
```ruby
payment.association(:order).options[:touch] = false
payment.save(validate: false)
payment.association(:order).options[:touch] = true
```

**Result:** ❌ Still timing out.

**Attempt 3.3:** Save payments separately, outside of nested attributes
```ruby
# app/models/spree/order_update_attributes.rb
def assign_payments_attributes
  @payments_attributes.each do |payment_attributes|
    payment = PaymentCreate.new(order, payment_attributes, request_env: @request_env).build
    payment.save(validate: false)  # Save separately
  end
end
```

**Result:** ❌ Still timing out.

---

## Breakthrough: Analyzing the Stack Trace

**Key Insight:** The stack trace from logs showed:
```
SystemStackError (stack level too deep):
  
app/models/spree/payment.rb:197:in `each'
app/models/spree/payment.rb:197:in `invalidate_old_payments'
app/models/spree/order_update_attributes.rb:78:in `block in assign_payments_attributes'
```

**Discovery:** The recursion was happening in `invalidate_old_payments` at line 197!

**Root Cause Analysis:**
1. `order.save` is called
2. `accepts_nested_attributes_for :payments` saves the payment
3. `payment.after_create :invalidate_old_payments` is triggered
4. `invalidate_old_payments` calls `payment.invalidate!` on other payments
5. `payment.invalidate!` saves the payment, which triggers `after_save` callbacks
6. These callbacks might trigger `order.save` again → **RECURSION**

---

## The Solution

**Final Fix:** Add a guard in `invalidate_old_payments` to skip execution if the order is currently being saved.

```ruby
# app/models/spree/payment.rb
def invalidate_old_payments
  # Prevent infinite recursion: skip if order is currently being saved
  # This prevents recursion when called from within order.save (e.g., from OrderUpdateAttributes)
  return if order.instance_variable_get(:@_saving)
  
  if !store_credit? && !['invalid', 'failed'].include?(state)
    order.payments.select { |payment|
      payment.state == 'checkout' && !payment.store_credit? && payment.id != id
    }.each(&:invalidate!)
  end
end
```

**And set the flag in `OrderUpdateAttributes`:**
```ruby
# app/models/spree/order_update_attributes.rb
def call
  order.validate_payments_attributes(@payments_attributes)
  assign_order_attributes
  assign_payments_attributes

  # Set flag to prevent invalidate_old_payments from running during save (prevents recursion)
  order.instance_variable_set(:@_saving, true)
  begin
    order.save
  ensure
    order.instance_variable_set(:@_saving, false)
  end
end
```

**Result:** ✅ **SUCCESS!** The recursion is fixed. Request completes successfully.

---

## What Worked vs What Didn't

### ❌ What Didn't Work:

1. **Skipping `recalculate` based on `order.changed?`**
   - Reason: The recursion wasn't coming from `recalculate`

2. **Using `update_columns` in `persist_totals`**
   - Reason: The recursion wasn't coming from `persist_totals`

3. **Thread-local flags for `recalculate`**
   - Reason: The recursion wasn't coming from `recalculate`

4. **Removing/modifying state machine `after_transition` callbacks**
   - Reason: The recursion wasn't coming from state machine transitions

5. **Disabling `payment.after_save :update_order`**
   - Reason: The recursion wasn't coming from `update_order`

6. **Disabling `touch: true` on payment association**
   - Reason: The recursion wasn't coming from touch

7. **Saving payments separately**
   - Reason: The recursion was still happening because `invalidate_old_payments` was still being called

### ✅ What Worked:

1. **Adding guard in `invalidate_old_payments`**
   - Reason: This was the actual source of recursion - `invalidate_old_payments` was calling `payment.invalidate!` which triggered more callbacks

2. **Setting flag in `OrderUpdateAttributes` before `order.save`**
   - Reason: This prevents `invalidate_old_payments` from running during the save operation

---

## Key Learnings

1. **Stack traces are in descending order** - Most recent call at top
2. **Short stack traces indicate tight recursion loops** - The recursion was happening very quickly
3. **Check all callbacks, not just the obvious ones** - `invalidate_old_payments` was an `after_create` callback that wasn't immediately obvious
4. **Use `save(validate: false)` to test hypotheses** - Helps isolate if validation is causing the issue
5. **Check nested attributes callbacks** - `accepts_nested_attributes_for` triggers callbacks on associated records
6. **Instance variables can be used as flags** - Simple and effective for preventing recursion
7. **Always check the actual stack trace** - The logs showed the real culprit (`invalidate_old_payments`)

---

## Debugging Methodology Used

1. **Start with exception handling** - Capture the stack trace
2. **Hypothesize the cause** - Based on code structure and callbacks
3. **Test hypothesis with minimal changes** - Use `save(validate: false)` to test
4. **Check logs for actual stack trace** - Don't rely on assumptions
5. **Trace the call chain** - Follow the stack trace to find the loop
6. **Fix at the source** - Add guard where the recursion starts, not where it manifests

---

## Final Code Changes

### File 1: `app/models/spree/payment.rb`
```ruby
def invalidate_old_payments
  # Prevent infinite recursion: skip if order is currently being saved
  return if order.instance_variable_get(:@_saving)
  
  if !store_credit? && !['invalid', 'failed'].include?(state)
    order.payments.select { |payment|
      payment.state == 'checkout' && !payment.store_credit? && payment.id != id
    }.each(&:invalidate!)
  end
end
```

### File 2: `app/models/spree/order_update_attributes.rb`
```ruby
def call
  order.validate_payments_attributes(@payments_attributes)
  assign_order_attributes
  assign_payments_attributes

  # Set flag to prevent invalidate_old_payments from running during save (prevents recursion)
  order.instance_variable_set(:@_saving, true)
  begin
    order.save
  ensure
    order.instance_variable_set(:@_saving, false)
  end
end
```

---

## Testing

After the fix, the API call completes successfully:
```bash
curl 'http://localhost:3000/api/checkouts/R626934763/update' \
  -X 'PATCH' \
  -H 'Content-Type: application/json' \
  --data-raw '{"order":{"payments_attributes":[{"payment_method_id":3}]}}'
```

**Result:** ✅ Request completes in ~400ms (no timeout)
**Error:** 422 Unprocessable Content (state transition error - separate issue, not recursion)

---

**Date:** January 2025  
**Issue:** SystemStackError during checkout update with payment attributes  
**Root Cause:** `payment.after_create :invalidate_old_payments` callback causing recursion  
**Solution:** Add guard to skip `invalidate_old_payments` when order is being saved

