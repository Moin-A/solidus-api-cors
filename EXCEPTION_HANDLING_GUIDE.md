# Rails Exception Handling with `rescue_from`

## Definition

**`rescue_from`** is a Rails controller class method that catches exceptions raised during controller actions and calls a specified handler method. Instead of wrapping every action in `begin/rescue/end` blocks, you declare exception handlers once at the class level.

### Basic Syntax

```ruby
rescue_from ExceptionClass, with: :handler_method_name
```

- **ExceptionClass**: The type of exception to catch (e.g., `CanCan::AccessDenied`, `ActiveRecord::RecordNotFound`)
- **with:**: The method name to call when this exception is raised
- **Handler method**: Must accept the exception as a parameter

---

## Complete Example

### Step 1: Declare the Exception Handler

```ruby
# app/controllers/spree/api/base_controller.rb
module Spree
  module Api
    class BaseController < ApplicationController
      # Declare exception handlers
      rescue_from CanCan::AccessDenied, with: :unauthorized
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      
      private
      
      # Handler methods - MUST accept exception parameter
      def unauthorized(exception)
        render json: { 
          error: 'You are not authorized to perform that action.',
          details: exception.message 
        }, status: :unauthorized
      end
      
      def not_found(exception)
        render json: { 
          error: 'The resource you were looking for could not be found.' 
        }, status: :not_found
      end
    end
  end
end
```

### Step 2: Raise Exception in Controller Action

```ruby
# app/controllers/spree/api/line_items_controller.rb
module Spree
  module Api
    class LineItemsController < BaseController
      # Inherits all rescue_from handlers from BaseController
      
      before_action :load_order
      
      def create
        # This code runs only if load_order succeeds
        @line_item = @order.contents.add(variant, quantity)
        render json: @line_item, status: :created
      end
      
      private
      
      def load_order
        @order = Spree::Order.find_by!(number: params[:order_id])
        
        # This raises CanCan::AccessDenied if user can't update order
        authorize! :update, @order
        
        # If exception is raised, Rails automatically calls unauthorized(exception)
      end
    end
  end
end
```

### Step 3: What Happens

```
1. User makes request: POST /api/orders/R123456/line_items
   ↓
2. load_order runs
   ↓
3. authorize! :update, @order checks permission
   ↓
   IF USER HAS PERMISSION:
   ✅ Continue to create action
   
   IF USER LACKS PERMISSION:
   ❌ CanCan raises CanCan::AccessDenied
   ↓
4. Rails catches exception (because of rescue_from line)
   ↓
5. Rails calls: unauthorized(exception)
   ↓
6. Response sent:
   {
     "error": "You are not authorized to perform that action.",
     "details": "Cannot update Order"
   }
```

---

## Key Points

1. **Handler method signature**: Always accept the exception parameter
   ```ruby
   # ✅ CORRECT
   def unauthorized(exception)
     render json: { error: exception.message }
   end
   
   # ❌ WRONG - Will crash
   def unauthorized
     render json: { error: 'Unauthorized' }
   end
   ```

2. **Inheritance**: Child controllers inherit parent's `rescue_from` handlers

3. **Order matters**: More specific exceptions before general ones
   ```ruby
   rescue_from CanCan::AccessDenied, with: :unauthorized     # Specific
   rescue_from StandardError, with: :internal_error          # General
   ```

4. **Common exceptions in our app**:
   - `CanCan::AccessDenied` → Authorization failed
   - `ActiveRecord::RecordNotFound` → Record not found in database
   - `ActionController::ParameterMissing` → Required parameter missing

---

## Quick Reference

```ruby
# In BaseController
rescue_from ExceptionClass, with: :handler_method

private

def handler_method(exception)
  # exception.class    - Exception type
  # exception.message  - Error message
  # exception.backtrace - Stack trace
  render json: { error: exception.message }, status: :some_status
end
```

**That's it!** You declare handlers with `rescue_from`, and Rails automatically calls them when exceptions are raised.
