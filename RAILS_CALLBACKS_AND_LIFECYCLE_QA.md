# Rails Callbacks and Lifecycle - Q&A

## Questions & Answers from Learning Session

This document covers Rails validation lifecycle, callbacks, and the order of execution in ActiveRecord models.

---

## Q1: Where does `self` come from in the validate block?

**Question:** In `Address.rb` lines 21-23, we have:
```ruby
validate do
  self.class.state_validator_class.new(self).perform
end
```

When we run `address.build(params)`, the validator needs an instance. Where is the record `self` coming from? Does the validator run after initialization but before save?

**Answer:** 

**Yes, your understanding is correct!** ✅

### The Flow

```ruby
# Step 1: Object is CREATED in memory (not saved)
@address = current_user.addresses.build(address_params)
# self NOW EXISTS ← Object created in Ruby memory

# Step 2: When you call save...
@address.save

# Step 3: BEFORE saving, Rails runs validations
# Including the custom validate block
```

### Timeline

```
build/new 
  ↓
Object exists in MEMORY (self = @address)
  ↓
save called
  ↓
Validations run (can access self)
  ↓
If valid: INSERT to database
If invalid: Don't save, populate errors
```

### What is `self`?

**`self` is the Address instance created by `build` or `new`**

```ruby
@address = Address.new(name: "John", city: "NYC")
#          ↑
# Object created in MEMORY (not in database yet)
# self = @address

@address.save
# Triggers validations
# In the validate block, self = @address
```

### Proof with Code

```ruby
address = Address.new(name: "John", city: "NYC")

# Object exists!
address.object_id        # => 12345 (has an object ID)
address.new_record?      # => true (not in DB yet)
address.persisted?       # => false (not saved)
address.name             # => "John" (has data)

# Now try to save - validations run
address.save
# Inside validate block:
#   self = address (the object we just created)
#   self.name => "John"
```

**Key Point:** The object doesn't need to be in the database to exist - it exists in Ruby memory from the moment you call `new` or `build`!

---

## Q2: Is `validate` just syntactic sugar for `before_save`?

**Question:** Is `validate` basically the same as `before_save`? Can we add any method that runs before save? Is `validate` just for checking things before save?

**Answer:**

**No, they're different!** There's an important distinction:

### `validate` - For Validation Logic

```ruby
validate :check_something

# Purpose: Check if data is valid
# Runs: BEFORE save (during validation phase)
# Can stop save: YES (by adding errors)
# Returns: Nothing (adds to errors)
```

### `before_save` - For Data Manipulation

```ruby
before_save :do_something

# Purpose: Modify/prepare data before saving
# Runs: AFTER validations pass, BEFORE database insert
# Can stop save: YES (return false or throw :abort)
# Returns: Should return truthy value to continue
```

### Complete Lifecycle

```ruby
object = Address.new(params)
object.save

# Order of operations:
# 1. before_validation callbacks
# 2. VALIDATIONS (validate blocks run here) ← Can stop save
#    - If invalid: STOP, return false
#    - If valid: Continue to step 3
# 3. after_validation callbacks
# 4. before_save callbacks ← Can stop save
# 5. before_create or before_update
# 6. INSERT/UPDATE to database
# 7. after_create/after_update
# 8. after_save
# 9. after_commit
```

### When to Use Each

**Use `validate` when:**
- ✅ Checking if data is valid
- ✅ Need to prevent save if conditions not met
- ✅ Want to add error messages

```ruby
validate :must_have_state

def must_have_state
  if country_iso == 'US' && state.blank?
    errors.add(:state, 'is required for US addresses')
  end
end
```

**Use `before_save` when:**
- ✅ Modifying data before it goes to database
- ✅ Computing derived values
- ✅ Setting defaults

```ruby
before_save :normalize_zipcode

def normalize_zipcode
  self.zipcode = zipcode.upcase if zipcode.present?
end
```

### Key Differences

| Feature | `validate` | `before_save` |
|---------|-----------|---------------|
| **Purpose** | Check validity | Modify data |
| **When** | Before save (validation phase) | After validation passes |
| **Stop save** | Add errors | `throw(:abort)` |
| **Use for** | Validation logic | Data preparation |

**`validate` is NOT syntactic sugar for `before_save` - they serve different purposes!**

---

## Q3: When does `after_commit` come in the lifecycle?

**Question:** When does `after_commit` run in relation to other callbacks?

**Answer:**

`after_commit` is special - it runs **AFTER the database transaction is committed**.

### Complete Rails Save Lifecycle

```ruby
address = Address.new(params)
address.save

# ┌─────────────────────────────────────────────┐
# │ PHASE 1: VALIDATION                         │
# └─────────────────────────────────────────────┘
# 1. before_validation
# 2. validate (all validation checks)
# 3. after_validation
#    ↓ If invalid: STOP
#    ↓ If valid: Continue...

# ┌─────────────────────────────────────────────┐
# │ PHASE 2: CALLBACKS (Before Transaction)    │
# └─────────────────────────────────────────────┘
# 4. before_save
# 5. before_create (new) or before_update (existing)
#    ↓ If returns false or throws :abort: STOP

# ┌─────────────────────────────────────────────┐
# │ PHASE 3: DATABASE TRANSACTION               │
# └─────────────────────────────────────────────┘
# BEGIN TRANSACTION ←─────────────────────┐
#                                          │
# 6. INSERT/UPDATE to database             │ INSIDE
#                                          │ TRANSACTION
# 7. after_create or after_update          │
#                                          │
# 8. after_save                            │
#                                          │
# COMMIT TRANSACTION ←─────────────────────┘
#    ↓ Transaction committed to disk
#    ↓ Data is now permanent

# ┌─────────────────────────────────────────────┐
# │ PHASE 4: AFTER TRANSACTION COMMITTED        │
# └─────────────────────────────────────────────┘
# 9. after_commit ← HERE! After data is saved
```

### Visual Timeline

```
before_validation
       ↓
   validate
       ↓
after_validation
       ↓
   [If invalid: STOP]
       ↓
before_save
       ↓
before_create/before_update
       ↓
═══════════════════════════════
  BEGIN TRANSACTION
───────────────────────────────
  INSERT/UPDATE (SQL)
───────────────────────────────
after_create/after_update
       ↓
after_save
───────────────────────────────
  COMMIT TRANSACTION  ✅ Data saved!
═══════════════════════════════
       ↓
after_commit  ← HERE! After commit
       ↓
   [Done]
```

### Why `after_commit` is Special

**Problem with `after_save`:**

```ruby
class Address < ApplicationRecord
  after_save :send_notification
  
  def send_notification
    AddressMailer.new_address(self).deliver_now
  end
end

# If email sending fails:
# - Transaction ROLLS BACK
# - But email was already sent! 😱
# - Database: No record
# - User: Got email about address that doesn't exist
```

**Solution with `after_commit`:**

```ruby
class Address < ApplicationRecord
  after_commit :send_notification, on: :create
  
  def send_notification
    AddressMailer.new_address(self).deliver_now
  end
end

# Now email only sends AFTER commit:
# - Transaction completes
# - Data is saved ✅
# - THEN email is sent ✅
```

### When to Use Each

**Use `after_save` for:**
- Updating related records in same transaction
- Logging within transaction

**Use `after_commit` for:**
- ✅ Sending emails
- ✅ Enqueuing background jobs
- ✅ Calling external APIs
- ✅ Cache invalidation
- ✅ Publishing events

---

## Q4: Can `before_save` and `before_create` be synonymous?

**Question:** If I need to check something before database transaction, can I use `before_save` or `before_create`? Why have two callbacks? Is there any nuance?

**Answer:**

**No, they're NOT synonymous!** They run at different times based on whether the record is **new** or **existing**.

### The Key Difference

```ruby
before_save    # Runs on BOTH create AND update
before_create  # Runs ONLY when creating new records
before_update  # Runs ONLY when updating existing records
```

### When Creating a New Record

```ruby
address = Address.new(name: "John")
address.save

# Callbacks that run:
# 1. before_validation
# 2. validate
# 3. after_validation
# 4. before_save        ← Runs ✅
# 5. before_create      ← Runs ✅ (new record)
# 6. INSERT INTO database
# 7. after_create       ← Runs ✅
# 8. after_save         ← Runs ✅
```

### When Updating an Existing Record

```ruby
address = Address.find(1)
address.name = "Jane"
address.save

# Callbacks that run:
# 1. before_validation
# 2. validate
# 3. after_validation
# 4. before_save        ← Runs ✅
# 5. before_update      ← Runs ✅ (existing record)
#    (before_create NOT called)
# 6. UPDATE database
# 7. after_update       ← Runs ✅
# 8. after_save         ← Runs ✅
```

### When to Use Each

**Use `before_save` when:**
You want logic to run on **BOTH create AND update**

```ruby
before_save :normalize_zipcode

def normalize_zipcode
  self.zipcode = zipcode.gsub(/\s/, '').upcase
  # Runs every time, whether new or updating
end
```

**Use `before_create` when:**
You want logic to run **ONLY on new records**

```ruby
before_create :generate_uuid

def generate_uuid
  self.uuid = SecureRandom.uuid
  # Only for new records
  # Don't change UUID when updating
end
```

**Use `before_update` when:**
You want logic to run **ONLY on existing records**

```ruby
before_update :track_changes

def track_changes
  if address1_changed?
    self.address_changed_at = Time.current
  end
end
```

### Summary

| Callback | New Records? | Existing Records? | Use When |
|----------|--------------|-------------------|----------|
| `before_save` | ✅ Yes | ✅ Yes | Logic for both |
| `before_create` | ✅ Yes | ❌ No | New records only |
| `before_update` | ❌ No | ✅ Yes | Updates only |

---

## Q5: If I have `before_save`, `before_create`, AND `before_update`, what is the order of execution?

**Question:** What is the execution order when I have all three callbacks defined?

**Answer:**

The order follows a pattern: **general → specific → database → specific → general**

### For NEW Records (Create)

```ruby
class Address < ApplicationRecord
  before_save :step_1
  before_create :step_2
  before_update :step_3
  
  after_create :step_4
  after_update :step_5
  after_save :step_6
end

address = Address.new(name: "John")
address.save

# Execution order:
# 1. before_save   :step_1    ✅ (general - runs on both)
# 2. before_create :step_2    ✅ (specific - new record)
#    before_update :step_3    ❌ (not called - not an update)
# 3. [INSERT INTO database]
# 4. after_create  :step_4    ✅ (specific - new record)
#    after_update  :step_5    ❌ (not called - not an update)
# 5. after_save    :step_6    ✅ (general - runs on both)
```

### For EXISTING Records (Update)

```ruby
address = Address.find(1)
address.name = "Jane"
address.save

# Execution order:
# 1. before_save   :step_1    ✅ (general - runs on both)
#    before_create :step_2    ❌ (not called - not new)
# 2. before_update :step_3    ✅ (specific - existing record)
# 3. [UPDATE database]
#    after_create  :step_4    ❌ (not called - not new)
# 4. after_update  :step_5    ✅ (specific - existing record)
# 5. after_save    :step_6    ✅ (general - runs on both)
```

### Complete Lifecycle - CREATE

```
┌─────────────────────────────────────┐
│ VALIDATION PHASE                    │
├─────────────────────────────────────┤
│ 1. before_validation                │
│ 2. validate                          │
│ 3. after_validation                  │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ BEFORE CALLBACKS                    │
├─────────────────────────────────────┤
│ 4. before_save      ← General first │
│ 5. before_create    ← Specific next │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ DATABASE                            │
├─────────────────────────────────────┤
│ 6. [BEGIN TRANSACTION]              │
│ 7. [INSERT INTO addresses]          │
│ 8. [COMMIT TRANSACTION]             │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ AFTER CALLBACKS                     │
├─────────────────────────────────────┤
│ 9. after_create     ← Specific first│
│ 10. after_save      ← General last  │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ POST-COMMIT                         │
├─────────────────────────────────────┤
│ 11. after_commit                    │
└─────────────────────────────────────┘
```

### Complete Lifecycle - UPDATE

```
┌─────────────────────────────────────┐
│ VALIDATION PHASE                    │
├─────────────────────────────────────┤
│ 1. before_validation                │
│ 2. validate                          │
│ 3. after_validation                  │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ BEFORE CALLBACKS                    │
├─────────────────────────────────────┤
│ 4. before_save      ← General first │
│ 5. before_update    ← Specific next │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ DATABASE                            │
├─────────────────────────────────────┤
│ 6. [BEGIN TRANSACTION]              │
│ 7. [UPDATE addresses]               │
│ 8. [COMMIT TRANSACTION]             │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ AFTER CALLBACKS                     │
├─────────────────────────────────────┤
│ 9. after_update     ← Specific first│
│ 10. after_save      ← General last  │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ POST-COMMIT                         │
├─────────────────────────────────────┤
│ 11. after_commit                    │
└─────────────────────────────────────┘
```

### The Pattern

**BEFORE callbacks:** Most general → Most specific
```
before_save         ← Runs first (broad)
  ↓
before_create/before_update  ← Runs second (specific)
```

**AFTER callbacks:** Most specific → Most general
```
after_create/after_update  ← Runs first (specific)
  ↓
after_save                 ← Runs second (broad)
```

### Why This Order?

**Before:** General first allows you to prepare data before specific operations

```ruby
before_save :normalize_all_data      # Prepare everything
before_create :set_creation_defaults  # Then set create-specific
```

**After:** Specific first allows you to handle specific operations before general cleanup

```ruby
after_create :send_welcome_email     # Handle create-specific
after_save :clear_cache              # Then do general cleanup
```

### Practical Example with Logging

```ruby
class Address < ApplicationRecord
  before_save :log_before_save
  before_create :log_before_create
  before_update :log_before_update
  
  after_create :log_after_create
  after_update :log_after_update
  after_save :log_after_save
  
  def log_before_save
    puts "1. before_save (runs for both)"
  end
  
  def log_before_create
    puts "2. before_create (only new)"
  end
  
  def log_before_update
    puts "2. before_update (only existing)"
  end
  
  def log_after_create
    puts "3. after_create (only new)"
  end
  
  def log_after_update
    puts "3. after_update (only existing)"
  end
  
  def log_after_save
    puts "4. after_save (runs for both)"
  end
end

# CREATE
Address.create(name: "John")
# Output:
# 1. before_save (runs for both)
# 2. before_create (only new)
# [INSERT]
# 3. after_create (only new)
# 4. after_save (runs for both)

# UPDATE
address.update(name: "Jane")
# Output:
# 1. before_save (runs for both)
# 2. before_update (only existing)
# [UPDATE]
# 3. after_update (only existing)
# 4. after_save (runs for both)
```

### Summary Table

| Operation | Order | Callback | Runs On |
|-----------|-------|----------|---------|
| **CREATE** | 1 | `before_save` | Create & Update |
|  | 2 | `before_create` | Create only |
|  | 3 | [INSERT] | - |
|  | 4 | `after_create` | Create only |
|  | 5 | `after_save` | Create & Update |
| **UPDATE** | 1 | `before_save` | Create & Update |
|  | 2 | `before_update` | Update only |
|  | 3 | [UPDATE] | - |
|  | 4 | `after_update` | Update only |
|  | 5 | `after_save` | Create & Update |

### Remember

- **Before:** General → Specific
- **After:** Specific → General
- `before_save` ALWAYS runs before `before_create`/`before_update`
- `after_create`/`after_update` ALWAYS run before `after_save`

---

## Complete ActiveRecord Lifecycle Chart

### All Phases in Order

```
┌─────────────────────────────────────────────────────────────┐
│ 1. INSTANTIATION                                            │
│    address = Address.new(params)                            │
│    - Object created in Ruby memory                          │
│    - Has attributes, but no ID                              │
│    - new_record? = true                                     │
│    - persisted? = false                                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
                   address.save called
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. VALIDATION PHASE                                         │
│    - before_validation                                       │
│    - validate (custom validations, built-in validations)    │
│    - after_validation                                        │
│                                                              │
│    If errors.any? → STOP, return false                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
                  Validations passed
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. BEFORE CALLBACKS (Pre-Transaction)                      │
│    - before_save (general)                                   │
│    - before_create (if new) OR before_update (if existing)  │
│                                                              │
│    If throw(:abort) or return false → STOP                  │
└─────────────────────────────────────────────────────────────┘
                          ↓
                    All checks passed
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. DATABASE TRANSACTION                                     │
│    ═══════════════════════════════════════                  │
│    BEGIN TRANSACTION                                         │
│    ───────────────────────────────────────                  │
│    INSERT INTO addresses ... (create)                       │
│    OR                                                        │
│    UPDATE addresses ... (update)                            │
│    ───────────────────────────────────────                  │
│    - Object gets ID (if new)                                │
│    - Attributes are persisted                                │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. AFTER CALLBACKS (Still in Transaction)                  │
│    - after_create (if new) OR after_update (if existing)    │
│    - after_save (general)                                    │
│    ───────────────────────────────────────                  │
│    COMMIT TRANSACTION                                        │
│    ═══════════════════════════════════════                  │
└─────────────────────────────────────────────────────────────┘
                          ↓
                Data committed to disk
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. POST-COMMIT CALLBACKS                                    │
│    - after_commit                                            │
│    - after_create_commit (if new)                           │
│    - after_update_commit (if existing)                      │
│                                                              │
│    Safe for: emails, background jobs, external APIs         │
└─────────────────────────────────────────────────────────────┘
                          ↓
                   save returns true
                          ↓
                 address.persisted? = true
```

---

## Real-World Example: Complete Address Model

```ruby
class Address < ApplicationRecord
  # VALIDATIONS
  validates :name, :address1, :city, :country_id, presence: true
  
  validate :custom_state_validation
  
  def custom_state_validation
    StateValidator.new(self).perform
  end
  
  # BEFORE CALLBACKS
  before_validation :strip_whitespace
  
  before_save :normalize_data
  
  before_create :set_uuid
  before_create :set_created_by
  
  before_update :track_last_modified
  
  # AFTER CALLBACKS (In Transaction)
  after_create :log_creation
  after_update :log_update
  
  after_save :update_user_cache
  
  # POST-COMMIT CALLBACKS
  after_create_commit :send_welcome_email
  after_update_commit :sync_with_external_api
  after_commit :clear_global_cache
  
  # ROLLBACK CALLBACK
  after_rollback :log_failure
  
  # Method definitions
  def strip_whitespace
    self.name = name.strip if name.present?
    self.address1 = address1.strip if address1.present?
  end
  
  def normalize_data
    self.zipcode = zipcode.upcase if zipcode.present?
  end
  
  def set_uuid
    self.uuid = SecureRandom.uuid
  end
  
  def set_created_by
    self.created_by_id = Current.user&.id
  end
  
  def track_last_modified
    self.last_modified_by_id = Current.user&.id
    self.last_modified_at = Time.current
  end
  
  def log_creation
    Rails.logger.info("Address created: #{id}")
  end
  
  def log_update
    Rails.logger.info("Address updated: #{id}, changes: #{saved_changes}")
  end
  
  def update_user_cache
    user.touch if user.present?
  end
  
  def send_welcome_email
    AddressMailer.new_address(self).deliver_later
  end
  
  def sync_with_external_api
    ExternalAddressSync.perform_later(id)
  end
  
  def clear_global_cache
    Rails.cache.delete("addresses_count")
  end
  
  def log_failure
    Rails.logger.error("Address save failed: #{errors.full_messages}")
  end
end
```

---

## Best Practices

### ✅ DO

1. **Use specific callbacks when possible**
   ```ruby
   before_create :set_uuid  # Only for new records
   ```

2. **Use `after_commit` for external operations**
   ```ruby
   after_commit :send_email  # Email only after DB save
   ```

3. **Keep callback methods simple**
   ```ruby
   before_save :normalize_zipcode
   
   def normalize_zipcode
     self.zipcode = zipcode.upcase
   end
   ```

4. **Use validations for data integrity**
   ```ruby
   validate :state_required_for_us
   ```

### ❌ DON'T

1. **Don't use `before_save` for validations**
   ```ruby
   # ❌ BAD
   before_save :check_valid
   def check_valid
     throw(:abort) if invalid?
   end
   
   # ✅ GOOD
   validate :check_valid
   def check_valid
     errors.add(:base, 'Invalid') if invalid?
   end
   ```

2. **Don't send emails in `after_save`**
   ```ruby
   # ❌ BAD - might send before commit
   after_save :send_email
   
   # ✅ GOOD - sends after commit
   after_commit :send_email
   ```

3. **Don't use `before_create` for data that changes**
   ```ruby
   # ❌ BAD - UUID would change on update
   before_save :generate_uuid
   
   # ✅ GOOD - UUID set once
   before_create :generate_uuid
   ```

---

## Quick Reference

### Callback Order

```
VALIDATION PHASE
  before_validation
  validate
  after_validation

BEFORE PHASE
  before_save
  before_create / before_update

DATABASE OPERATION
  BEGIN TRANSACTION
  INSERT / UPDATE
  
AFTER PHASE (In Transaction)
  after_create / after_update
  after_save
  COMMIT TRANSACTION

POST-COMMIT PHASE
  after_commit
```

### Callback Decision Tree

```
Do you need to validate data?
  YES → use validate
  NO  ↓

Does it run on both create and update?
  YES → use before_save / after_save
  NO  ↓

Does it run only on new records?
  YES → use before_create / after_create
  NO  ↓

Does it run only on updates?
  YES → use before_update / after_update
  NO  ↓

Does it need guaranteed database commit?
  YES → use after_commit
  NO  → use regular callbacks
```

---

**Created:** October 21, 2025  
**Topic:** Rails ActiveRecord Callbacks and Lifecycle  
**Source:** Solidus Address Model Implementation

