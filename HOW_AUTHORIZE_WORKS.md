# How `authorize!` Knows the Current User

## The Question

When we call:
```ruby
authorize! :update, @order, order_token
```

**How does `authorize!` know who the current user is?** We don't pass the user as an argument!

---

## The Answer: The Complete Chain

### Step 1: `authorize!` Calls `current_ability`

When you call `authorize!`, CanCan internally does this:

```ruby
# Inside CanCan gem (simplified)
def authorize!(action, subject, *args)
  # It automatically calls current_ability to get the ability object
  ability = current_ability  # ← Gets current user's permissions
  
  unless ability.can?(action, subject, *args)
    raise CanCan::AccessDenied
  end
end
```

### Step 2: `current_ability` is Defined in BaseController

**File: `app/controllers/spree/api/base_controller.rb` (Line 107-109)**

```ruby
def current_ability
  Spree::Ability.new(current_api_user)  # ← Passes current user here!
end
```

**This is the magic!** `current_ability` creates a new `Spree::Ability` object and passes `current_api_user` to it.

### Step 3: `Spree::Ability` Loads the User's Roles and Permissions

**File: `app/models/spree/ability.rb` (Line 29-34)**

```ruby
def initialize(current_user)
  @user = current_user || Spree.user_class.new  # ← Stores the user
  
  activate_permission_sets  # ← Loads permissions for user's roles
  register_extension_abilities
end

def activate_permission_sets
  # This loads all permission sets for the user's roles
  Spree::Config.roles.activate_permissions! self, user
end
```

### Step 4: Permission Sets Are Activated

For a user with the "customer" role, `activate_permission_sets` loads `DefaultCustomer`:

```ruby
# Inside DefaultCustomer permission set
def initialize(ability)
  @ability = ability
end

def activate!
  # 'user' here refers to @ability.user (the current_api_user)
  can :create, Order do |order, token|
    order.user == user ||  # ← 'user' is current_api_user!
    order.email.present? ||
    (order.guest_token.present? && token == order.guest_token)
  end
end
```

---

## Complete Visual Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ Controller: LineItemsController                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  before_action :load_user                                       │
│    ↓ Sets @current_api_user (from cookie)                       │
│                                                                  │
│  def load_order                                                 │
│    authorize! :update, @order, order_token  ←──┐                │
│  end                                           │                │
└────────────────────────────────────────────────┼────────────────┘
                                                 │
                                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│ CanCan Gem: authorize! method                                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  def authorize!(action, subject, *args)                         │
│    ability = current_ability  ←──────────────┐                  │
│    unless ability.can?(action, subject, *args)                  │
│      raise CanCan::AccessDenied              │                  │
│    end                                        │                  │
│  end                                          │                  │
└───────────────────────────────────────────────┼──────────────────┘
                                                │
                                                ▼
┌──────────────────────────────────────────────────────────────────┐
│ BaseController: current_ability method                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  def current_ability                                            │
│    Spree::Ability.new(current_api_user)  ←──┐                   │
│  end                                        │                   │
│                                             │                   │
│  @current_api_user = user from cookie      │                   │
│  (set in load_user before_action)          │                   │
└─────────────────────────────────────────────┼───────────────────┘
                                              │
                                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Spree::Ability: initialize                                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  def initialize(current_user)                                   │
│    @user = current_user  # ← Stores current_api_user           │
│    activate_permission_sets  ←──────────────┐                   │
│  end                                        │                   │
└─────────────────────────────────────────────┼───────────────────┘
                                              │
                                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Permission Sets: DefaultCustomer                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  def activate!                                                  │
│    # 'user' here refers to current_api_user                     │
│    can :update, Order do |order, token|                         │
│      order.user == user  # ← Comparing against current user    │
│    end                                                          │
│  end                                                            │
└──────────────────────────────────────────────────────────────────┘
```

---

## What About `order_token`?

### Question: Why do we pass `order_token` to `authorize!`?

```ruby
authorize! :update, @order, order_token
```

### Answer: Guest Checkout Support

The `order_token` is used for **guest checkout** - when users shop without logging in.

**From DefaultCustomer permission set (line 57-59):**

```ruby
can [:show, :update], Order, Order.where(user:) do |order, token|
  order.user == user ||  # Logged-in user's own order
  (order.guest_token.present? && token == order.guest_token)  # ← Guest order
end
```

**Two scenarios:**

1. **Logged-in user**: `order.user == current_api_user` → Authorized ✅
2. **Guest user**: `order.guest_token == order_token` → Authorized ✅

**In our case (`order_token` is aliased to `api_key`):**

```ruby
# BaseController line 80
alias :order_token :api_key

# So when we call:
authorize! :update, @order, order_token

# CanCan checks:
# - Does order.user == current_api_user? (for logged-in users)
# - Does order.guest_token == api_key? (for guest checkout)
```

---

## Summary

| What | Where | Purpose |
|------|-------|---------|
| `authorize!` | CanCan gem | Entry point - checks permission |
| `current_ability` | BaseController (line 107) | Creates ability object with current user |
| `current_api_user` | Set by `load_user` before_action | The logged-in user |
| `Spree::Ability.new(user)` | Spree gem | Loads user's roles and permission sets |
| `activate_permission_sets` | Spree::Ability (line 47) | Activates all permission sets for user's roles |
| `DefaultCustomer#activate!` | Permission set | Defines what "customer" role can do |
| `user` (in permission set) | Delegated from ability | References current_api_user |
| `order_token` | Extra argument | For guest checkout support |

---

## Key Insight

**`authorize!` doesn't need the user passed as an argument because:**

1. It calls `current_ability`
2. `current_ability` calls `Spree::Ability.new(current_api_user)`
3. `Spree::Ability` stores the user internally as `@user`
4. Permission sets access this user via `user` method (delegated from ability)

**The chain is:**
```
authorize! → current_ability → Spree::Ability.new(current_api_user) → @user → permission sets
```

---

## Real Example from Your Code

```ruby
# 1. User makes request with cookie containing spree_api_key
POST /api/orders/R123456/line_items

# 2. before_action :load_user runs (BaseController line 46)
@current_api_user = Spree::User.find_by(spree_api_key: api_key)
# Result: @current_api_user = #<Spree::User id: 5, email: "user@example.com">

# 3. load_order runs
@order = Spree::Order.find_by!(number: 'R123456')
# Result: @order = #<Spree::Order id: 10, user_id: 5>

# 4. authorize! is called
authorize! :update, @order, order_token

# 5. CanCan calls current_ability
current_ability
  ↓ calls Spree::Ability.new(current_api_user)
    ↓ stores @user = current_api_user (user #5)
      ↓ activates DefaultCustomer permission set
        ↓ checks: order.user (user #5) == user (user #5) ✅
          ↓ Result: AUTHORIZED!

# 6. Controller continues to create action
```

---

**Bottom Line:** The user is passed implicitly through the `current_ability` method, which creates a `Spree::Ability` object with `current_api_user`. This is a common Rails pattern called **convention over configuration** - the framework knows where to find the current user without you having to pass it explicitly.

