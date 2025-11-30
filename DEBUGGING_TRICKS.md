# Debugging Tricks for Rails/Solidus Development

A collection of debugging techniques and tricks for troubleshooting Rails applications, especially when dealing with complex frameworks like Solidus.

---

## Table of Contents
1. [Exception Handling & Stack Traces](#exception-handling--stack-traces)
2. [Validation Bypassing](#validation-bypassing)
3. [Call Stack Analysis](#call-stack-analysis)
4. [State Machine Debugging](#state-machine-debugging)
5. [ActiveRecord Debugging](#activerecord-debugging)
6. [Quick Cheat: How to Debug Migration Issues](#quick-cheat-how-to-debug-migration-issues)
7. [Common Patterns](#common-patterns)

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

## Quick Cheat: How to Debug Migration Issues

### Finding Table and Index Names

When you need to rollback a migration or fix migration errors, you need to know the exact table and index names. Here are multiple methods:

#### Method 1: Check the Migration File (Most Reliable)

```bash
# Find migration files
find db/migrate -name "*your_table*"

# Read the migration
cat db/migrate/20251125134311_spree_products_rating.rb
```

Look for:
- `create_table :table_name` → This is your table name
- `add_index :table_name, [...], name: 'index_name'` → This is your index name

#### Method 2: Check db/schema.rb

```bash
# Search for the table in schema
grep -A 10 "create_table.*your_table" db/schema.rb

# Search for indexes
grep "add_index.*your_table" db/schema.rb
```

The schema file shows the current database structure after all migrations.

#### Method 3: Query the Database via Rails

```ruby
# In Rails console
bin/rails console

# Check if table exists
ActiveRecord::Base.connection.table_exists?('spree_products_spree_ratings')

# Get all columns
ActiveRecord::Base.connection.columns('spree_products_spree_ratings').map(&:name)

# Get all indexes
ActiveRecord::Base.connection.indexes('spree_products_spree_ratings').map(&:name)

# List all tables
ActiveRecord::Base.connection.tables.grep(/rating/)
```

#### Method 4: Use PostgreSQL Directly

```bash
# Connect to PostgreSQL
psql -U your_username -d solidus_api_development

# Describe the table
\d spree_products_spree_ratings

# Query system tables for indexes
SELECT indexname FROM pg_indexes WHERE tablename = 'spree_products_spree_ratings';
```

#### Method 5: Check Migration Status

```bash
# See all migrations and their status
bin/rails db:migrate:status

# Find migrations that created a table
grep -r "create_table.*your_table" db/migrate/
```

### Common Migration Errors and Fixes

#### Error: `NameError: uninitialized constant SpreeProductsRating`

**Problem:** Migration file contains model code instead of migration code.

**Wrong:**
```ruby
module Spree
  class SpreeProductsRating < Spree::Base  # ❌ This is a MODEL!
    belongs_to :product
  end
end
```

**Correct:**
```ruby
class SpreeProductsRating < ActiveRecord::Migration[7.2]  # ✅ Migration class
  def up
    drop_table :spree_products_spree_ratings if table_exists?(:spree_products_spree_ratings)
  end

  def down
    create_table :spree_products_spree_ratings do |t|
      t.references :product, foreign_key: { to_table: :spree_products }
      t.references :rating, foreign_key: { to_table: :spree_ratings }
      t.timestamps
    end
    add_index :spree_products_spree_ratings, [:product_id, :rating_id], unique: true
  end
end
```

#### Error: `PG::UndefinedTable: ERROR: relation "spree_spree_products_spree_ratings" does not exist`

**Problem:** Rails is inferring wrong table name (double namespace prefix).

**Solution:** Explicitly set table name in the model:

```ruby
module Spree
  class SpreeProductsSpreeRating < Spree::Base
    self.table_name = 'spree_products_spree_ratings'  # ✅ Explicit table name
    belongs_to :product
    belongs_to :rating
  end
end
```

**Why:** When class name starts with namespace name (`Spree::SpreeProductsSpreeRating`), Rails adds namespace prefix twice, creating `spree_spree_products_spree_ratings` instead of `spree_products_spree_ratings`.

### Rollback Commands Cheat Sheet

```bash
# Rollback last migration
bin/rails db:rollback

# Rollback multiple steps
bin/rails db:rollback STEP=3

# Rollback to specific version
bin/rails db:migrate VERSION=20251118110548

# Rollback specific migration
bin/rails db:migrate:down VERSION=20251125134311

# Re-run specific migration
bin/rails db:migrate:up VERSION=20251125134311

# Check migration status
bin/rails db:migrate:status
```

### Migration Debugging Workflow

1. **Check what's applied:**
   ```bash
   bin/rails db:migrate:status
   ```

2. **Find the migration file:**
   ```bash
   find db/migrate -name "*your_table*"
   cat db/migrate/YYYYMMDDHHMMSS_migration_name.rb
   ```

3. **Check current database state:**
   ```ruby
   # Rails console
   ActiveRecord::Base.connection.table_exists?('table_name')
   ActiveRecord::Base.connection.indexes('table_name')
   ```

4. **Fix the migration file** (if needed):
   - Ensure it's a migration class, not a model
   - Check table names match
   - Verify `up` and `down` methods exist

5. **Test rollback:**
   ```bash
   bin/rails db:rollback
   ```

6. **Re-run if needed:**
   ```bash
   bin/rails db:migrate
   ```

### Quick Reference: Finding Table/Index Names

```bash
# 1. Find migration files
find db/migrate -name "*your_table*"

# 2. Check schema
grep "create_table.*your_table" db/schema.rb

# 3. Rails console
bin/rails runner "puts ActiveRecord::Base.connection.tables.grep(/your_table/)"

# 4. PostgreSQL
psql -d your_database -c "\d your_table_name"
```

### Common Mistakes to Avoid

❌ **Don't put model code in migration files**
- Migrations should only contain database schema changes
- Models should be in `app/models/`

❌ **Don't forget to set `self.table_name` for namespaced models**
- If class name starts with namespace name, explicitly set table name

❌ **Don't rollback in production without backup**
- Always backup database before rollback in production

✅ **Do check migration status before rollback**
- `bin/rails db:migrate:status` shows what's applied

✅ **Do test migrations in development first**
- Test both `up` and `down` methods

✅ **Do keep migration files simple**
- One migration = one logical change

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

## Zeitwerk Autoloading Debugging

### Checking Zeitwerk Autoloading Issues

When deploying or running in production, Zeitwerk (Rails' autoloader) may fail to load constants. Use this command to check for autoloading issues:

```bash
# Check Zeitwerk autoloading in production environment
RAILS_ENV=production SECRET_KEY_BASE=dummy rails zeitwerk:check
```

**Note:** You may need to provide a `SECRET_KEY_BASE` even for checking, as some initializers require it. Use a dummy value if you don't have the production key locally.

### Common Zeitwerk Errors

#### Error: `invalid configuration option :public_url`

**Problem:** Using an invalid option in `config/storage.yml` or other configuration files.

**Solution:** Remove invalid options. For example, `public_url` is not a valid option for Active Storage S3 service in Rails 7.2. Use an initializer instead:

```ruby
# config/initializers/active_storage_cloudfront.rb
if Rails.env.production? && Rails.application.config.active_storage.service == :amazon
  ActiveSupport.on_load(:active_storage_blob) do
    require 'active_storage/service/s3_service'
    
    ActiveStorage::Service::S3Service.class_eval do
      alias_method :original_url, :url
      
      def url(key, expires_in:, filename:, disposition:, content_type:)
        cloudfront_base = ENV.fetch("CLOUDFRONT_URL", "https://d3687nk8qb4e0v.cloudfront.net").chomp("/")
        "#{cloudfront_base}/#{key}"
      end
    end
  end
end
```

#### Error: `uninitialized constant ActiveStorage::Service::S3Service`

**Problem:** Trying to access a constant before it's loaded in an initializer.

**Solution:** Use `ActiveSupport.on_load` to ensure the constant is loaded:

```ruby
# ❌ Wrong - constant not loaded yet
ActiveStorage::Service::S3Service.class_eval do
  # ...
end

# ✅ Correct - wait for constant to load
ActiveSupport.on_load(:active_storage_blob) do
  require 'active_storage/service/s3_service'
  ActiveStorage::Service::S3Service.class_eval do
    # ...
  end
end
```

#### Error: `NameError: uninitialized constant`

**Problem:** File naming doesn't match constant name, or constant is referenced before it's loaded.

**Solutions:**
1. Ensure file names match constant names (e.g., `user_profile.rb` → `UserProfile` class)
2. Don't manually require files in autoload paths
3. Use `ActiveSupport.on_load` hooks for initializers that modify classes
4. Check that all directories are in `config.eager_load_paths` if needed

### Zeitwerk Debugging Workflow

1. **Run Zeitwerk check:**
   ```bash
   RAILS_ENV=production SECRET_KEY_BASE=dummy rails zeitwerk:check
   ```

2. **If errors occur, check:**
   - Configuration files for invalid options
   - Initializers that modify classes (use `on_load` hooks)
   - File naming matches constant names
   - All required constants are loaded before use

3. **Fix the issue:**
   - Remove invalid configuration options
   - Use proper loading hooks in initializers
   - Fix file/constant naming mismatches

4. **Re-run check:**
   ```bash
   RAILS_ENV=production SECRET_KEY_BASE=dummy rails zeitwerk:check
   ```

### Quick Reference: Zeitwerk Commands

```bash
# Check autoloading (development)
rails zeitwerk:check

# Check autoloading (production - requires SECRET_KEY_BASE)
RAILS_ENV=production SECRET_KEY_BASE=dummy rails zeitwerk:check

# Check with specific environment variables
RAILS_ENV=production SECRET_KEY_BASE=your_key rails zeitwerk:check
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

