# Solidus API CORS - Role & Permissions Guide

## Table of Contents

- [How to Check Role Permissions](#how-to-check-role-permissions)
- [Customer Role Implementation](#customer-role-implementation)
- [Testing Permissions](#testing-permissions)

---

## How to Check Role Permissions

### In Rails Console

Open Rails console: `rails console`

#### 1. Check Role Configuration

```ruby
# Check if customer role exists
customer_role = Spree::Role.find_by(name: 'customer')
puts customer_role&.name

# Check what permission sets are configured for customer role
customer_role_config = Spree::Config.roles.instance_variable_get(:@roles)["customer"]
permission_sets = customer_role_config.instance_variable_get(:@permission_sets).to_a
puts permission_sets
# => [Spree::PermissionSets::DefaultCustomer]
```

#### 2. Check User's Roles

```ruby
# Find a user (replace with actual user)
user = Spree::User.first
puts "User roles: #{user.spree_roles.pluck(:name)}"

# Check if user has customer role
puts "Has customer role: #{user.spree_roles.exists?(name: 'customer')}"
```

#### 3. Check Specific Permissions

```ruby
# Create a test order to check permissions
test_order = Spree::Order.new(user: user, store: Spree::Store.default)

# Check permissions using CanCan (this is what Spree uses internally)
ability = Spree::PermissionSets::DefaultCustomer.new(user)
ability.activate!

# Test specific permissions
puts "Can create Order: #{ability.can?(:create, Spree::Order)}"
puts "Can create test order: #{ability.can?(:create, test_order)}"
puts "Can update Order: #{ability.can?(:update, Spree::Order)}"
puts "Can read Product: #{ability.can?(:read, Spree::Product)}"
```

#### 4. Find or Create Customer Users

```ruby
# Find a user with customer role
customer_user = Spree::User.joins(:spree_roles).where(spree_roles: { name: 'customer' }).first
puts customer_user&.email
puts customer_user&.spree_roles&.pluck(:name)

# Create a test customer user if none exists
customer_role = Spree::Role.find_by(name: 'customer')
user = Spree::User.create!(email: 'test@example.com', password: 'password123')
user.spree_roles << customer_role
user.generate_spree_api_key!
```

---

## Customer Role Implementation

### Overview

Spree's authorization system uses **CanCan** with a role-permission system:

1. **Roles** (stored in `spree_roles` table) - e.g., "admin", "customer"
2. **Permission Sets** (classes in `app/models/spree/permission_sets/`) - define what each role can do
3. **Role Configuration** (in `config/initializers/spree.rb`) - maps roles to permission sets

Good news: **DefaultCustomer permission set already exists** with cart/order management abilities!

---

### Implementation Steps

#### 1. Create "customer" Role in Database

**File: `db/seeds.rb`**

Add to seeds file:

```ruby
# Create customer role if it doesn't exist
Spree::Role.find_or_create_by!(name: 'customer')
```

Then run: `rails db:seed`

---

#### 2. Configure Permissions for "customer" Role

**File: `config/initializers/spree.rb`**

After the custom permissions comment (around line 29), add:

```ruby
# Assign DefaultCustomer permissions to customer role
config.roles.assign_permissions :customer, ['Spree::PermissionSets::DefaultCustomer']
```

**What DefaultCustomer includes:**

- Create, read, update Orders (for own orders)
- Read products, variants, taxons
- Manage own credit cards
- Create refund authorizations
- Update own user profile

---

#### 3. Auto-assign "customer" Role During Registration

**File: `app/controllers/api/auth_controller.rb`**

In the `register` method, after `user.save`, add:

```ruby
if user.save
  # Generate API key if it doesn't exist
  user.generate_spree_api_key! unless user.spree_api_key
  
  # Assign customer role
  customer_role = Spree::Role.find_by(name: 'customer')
  user.spree_roles << customer_role if customer_role && !user.spree_roles.include?(customer_role)
  
  # Set cookie
  cookies.encrypted[:spree_api_key] = {
    value: user.spree_api_key,
    httponly: true,
    secure: Rails.env.production?,
    same_site: :lax
  }
  
  render json: { 
    message: 'User created successfully', 
    user: { email: user.email, api_key: user.spree_api_key }
  }, status: :created
else
  render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
end
```

Also update the `login` method to assign customer role to existing users without roles:

```ruby
def login
  user = Spree::User.find_by(email: params[:email])
  
  if user&.valid_password?(params[:password])
    # Generate API key if it doesn't exist
    user.generate_spree_api_key! unless user.spree_api_key
    
    # Assign customer role if user has no roles
    if user.spree_roles.empty?
      customer_role = Spree::Role.find_by(name: 'customer')
      user.spree_roles << customer_role if customer_role
    end
    
    # Rest of login logic...
  end
end
```

---

#### 4. (Optional) Handle Existing Users

For users created before this change, run a one-time update in Rails console:

```ruby
# Assign customer role to all users who have no roles
Spree::User.left_joins(:spree_roles)
  .where(spree_roles: { id: nil })
  .find_each do |user|
    customer_role = Spree::Role.find_by(name: 'customer')
    user.spree_roles << customer_role if customer_role
  end
```

---

## Testing Permissions

### After Implementation

1. **Register a new user:**
   ```bash
   curl -X POST http://localhost:3001/api/auth/register \
     -H "Content-Type: application/json" \
     -d '{"email":"newuser@example.com","password":"password123","password_confirmation":"password123"}'
   ```

2. **Verify user has "customer" role:**
   ```ruby
   user = Spree::User.find_by(email: 'newuser@example.com')
   user.spree_roles.pluck(:name)
   # Should return: ["customer"]
   ```

3. **Test cart operations:**
   ```bash
   # Add item to cart (using the cookie from registration)
   curl -X POST http://localhost:3001/api/orders/current/line_items \
     -H "Content-Type: application/json" \
     -H "Cookie: spree_api_key=YOUR_API_KEY" \
     -d '{"line_item":{"variant_id":8,"quantity":1}}'
   ```

4. **Should succeed without "unauthorized" error**

---

## Files Modified

- `db/seeds.rb` - Add customer role creation
- `config/initializers/spree.rb` - Configure customer permissions  
- `app/controllers/api/auth_controller.rb` - Auto-assign role on registration/login
- `app/models/spree/permission_sets/default_customer.rb` - Updated to allow creating orders

---

## Debugging Tips

### Check if authorization is the issue

Add `binding.pry` in:
- `app/controllers/spree/api/base_controller.rb` → `load_user` method
- `app/models/spree/permission_sets/default_customer.rb` → `activate!` method

### Check current user context

```ruby
current_api_user.spree_roles.pluck(:name)  # Should include "customer"
current_api_user.spree_api_key            # Should match cookie value
```

### Inspect order permissions

```ruby
order = Spree::Order.find_by(number: 'R123456789')
ability = Spree::PermissionSets::DefaultCustomer.new(current_api_user)
ability.activate!
ability.can?(:update, order)  # Should be true for user's own order
```

---

## Common Issues

### Issue: "You are not authorized to perform that action"

**Cause:** User doesn't have customer role

**Solution:**
```ruby
user = Spree::User.find_by(email: 'user@example.com')
customer_role = Spree::Role.find_by(name: 'customer')
user.spree_roles << customer_role if customer_role
```

### Issue: "Order not found" for `order_id: 'current'`

**Cause:** `load_order` doesn't handle 'current' properly

**Solution:** Already implemented in `app/controllers/spree/api/line_items_controller.rb` - finds or creates user's cart

### Issue: Permissions work in console but not in API

**Cause:** Cookie not being sent or API key not matching

**Solution:**
1. Check browser DevTools → Network → Request Headers → Cookie
2. Verify cookie value matches `user.spree_api_key` in database
3. Ensure frontend sends `credentials: 'include'` in fetch requests

---

## Architecture Notes

### Controller Inheritance

```
ApplicationController
  ↓
Spree::Api::BaseController (overridden at app level)
  ↓
Spree::Api::LineItemsController (overridden at app level)
```

This ensures all Spree API controllers use our custom authentication logic.

### Permission Set Activation Flow

1. Request comes in → `Spree::Api::BaseController#load_user`
2. User loaded by `spree_api_key` from cookie
3. `Spree::Api::BaseController#load_user_roles` loads user's roles
4. CanCan automatically activates permission sets for each role
5. `authorize!` checks if action is allowed

---

## Additional Resources

- [Solidus Permissions Guide](https://guides.solidus.io/developers/users/permissions.html)
- [CanCanCan Documentation](https://github.com/CanCanCommunity/cancancan)
- [Spree Role Configuration](https://github.com/solidusio/solidus/blob/master/core/lib/spree/core/role_configuration.rb)
