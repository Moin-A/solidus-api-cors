# Shipping Methods API Documentation

## Overview
This document describes the available API endpoints for retrieving shipping methods and rates for orders.

## Endpoints

### 1. Get All Available Shipping Methods
Returns all shipping methods configured in the system (not order-specific).

**Endpoint:** `GET /api/shipping_methods`

**Authentication:** Not required

**Response:**
```json
[
  {
    "id": 11,
    "name": "India Standard Shipping",
    "admin_name": "India Standard",
    "tracking_url": null,
    "created_at": "2025-10-15T19:00:25.375Z",
    "updated_at": "2025-10-15T19:00:25.375Z"
  }
]
```

**Use Case:** Display available shipping methods to users before they create an order.

---

### 2. Get Available Shipping Methods for Specific Order (NEW)
Returns available shipping methods calculated specifically for an order based on:
- Shipping address
- Order items
- Stock location
- Shipping zones

**Endpoint:** `GET /api/orders/:id/available_shipping_methods`

**Authentication:** Required (must be order owner)

**Prerequisites:**
- Order must have a shipping address
- Order must have shipments created (typically happens when moving from `address` to `delivery` state)

**Response:**
```json
{
  "order_id": 12,
  "order_state": "delivery",
  "shipping_methods": [
    {
      "id": 11,
      "name": "India Standard Shipping",
      "cost": 50.0,
      "display_cost": "₹50.0",
      "selected": true,
      "shipping_rate_id": 24,
      "shipment_id": 132,
      "tax_category": null,
      "admin_name": "India Standard",
      "tracking_url": null
    }
  ],
  "message": "Available shipping methods for order #R051019643"
}
```

**Error Response (422):**
```json
{
  "error": "Order must have a shipping address before shipping methods can be determined"
}
```

**Use Case:** 
- Display shipping options during checkout
- Show calculated shipping costs for user's specific address
- Allow user to select preferred shipping method

---

### 3. Get Order with Shipping Information
Returns complete order details including shipments and their shipping rates.

**Endpoint:** `GET /api/orders/:id`

**Authentication:** Required (must be order owner)

**Response:**
```json
{
  "id": 12,
  "number": "R051019643",
  "state": "delivery",
  "total": "364.29",
  "shipment_total": "100.0",
  "line_items": [...],
  "bill_address": {...},
  "ship_address": {
    "id": 3,
    "address1": "Bhoomkar chowk",
    "city": "Pune",
    "state_name": "Assam"
  },
  "shipments": [
    {
      "id": 132,
      "number": "H52036628720",
      "cost": "50.0",
      "state": "pending",
      "shipping_rates": [
        {
          "id": 24,
          "shipment_id": 132,
          "shipping_method_id": 11,
          "selected": true,
          "cost": "50.0"
        }
      ]
    }
  ],
  "payments": [...]
}
```

---

## Workflow Example

### Checkout Flow with Shipping Selection

```javascript
// Step 1: User adds items to cart
POST /api/cart/add_item
{
  "variant_id": 10,
  "quantity": 1
}

// Step 2: User enters shipping address
PUT /spree/api/checkouts/:order_number
{
  "order": {
    "ship_address_attributes": {
      "firstname": "John",
      "lastname": "Doe",
      "address1": "123 Main St",
      "city": "Mumbai",
      "state_id": 1,
      "country_id": 1,
      "zipcode": "400001",
      "phone": "9876543210"
    }
  },
  "state": "address"
}

// Step 3: Get available shipping methods for this order
GET /api/orders/:id/available_shipping_methods

Response:
{
  "order_id": 12,
  "shipping_methods": [
    {
      "id": 11,
      "name": "India Standard Shipping",
      "cost": 50.0,
      "display_cost": "₹50.0",
      "shipping_rate_id": 24,
      "shipment_id": 132
    },
    {
      "id": 12,
      "name": "India Express Shipping",
      "cost": 150.0,
      "display_cost": "₹150.0",
      "shipping_rate_id": 25,
      "shipment_id": 132
    }
  ]
}

// Step 4: User selects shipping method
PUT /spree/api/checkouts/:order_number
{
  "order": {
    "shipments_attributes": [
      {
        "id": 132,
        "selected_shipping_rate_id": 24
      }
    ]
  },
  "state": "delivery"
}

// Step 5: Proceed to payment
PUT /spree/api/checkouts/:order_number
{
  "state": "payment"
}
```

---

## Key Differences

### `/api/shipping_methods` vs `/api/orders/:id/available_shipping_methods`

| Feature | `/api/shipping_methods` | `/api/orders/:id/available_shipping_methods` |
|---------|-------------------------|---------------------------------------------|
| **Context** | System-wide | Order-specific |
| **Pricing** | No pricing info | Calculated cost for this order |
| **Filtering** | Shows all methods | Filtered by address, zones, availability |
| **Use Case** | General information | Checkout process |
| **Auth Required** | No | Yes |
| **Prerequisites** | None | Order with shipping address |

---

## Technical Details

### How Shipping Methods Are Calculated

The system uses `Spree::Stock::Estimator` to calculate available shipping methods:

1. **Address Matching**: Filters shipping methods by zones matching the order's shipping address
2. **Calculator**: Runs each shipping method's calculator to determine cost
3. **Availability**: Checks if method is available for the store and package contents
4. **Tax Calculation**: Applies shipping taxes based on tax categories
5. **Sorting**: Sorts rates (default: by cost ascending)
6. **Selection**: Marks the cheapest/default rate as selected

### Refresh Rates

Call `shipment.refresh_rates` to recalculate shipping rates when:
- Address changes
- Items added/removed from order
- Shipping methods updated in admin

---

## Related Models

- **Spree::ShippingMethod** - Defines available shipping carriers/options
- **Spree::ShippingRate** - Calculated rate for a specific shipment
- **Spree::Shipment** - Physical package of items being shipped
- **Spree::Zone** - Geographic area for shipping method availability

---

## Example: Multiple Shipping Methods

If your system has multiple shipping methods configured:

```json
{
  "order_id": 15,
  "shipping_methods": [
    {
      "id": 11,
      "name": "India Standard Shipping",
      "cost": 50.0,
      "selected": true,
      "admin_name": "Standard Delivery (5-7 days)"
    },
    {
      "id": 12,
      "name": "India Express Shipping",
      "cost": 150.0,
      "selected": false,
      "admin_name": "Express Delivery (2-3 days)"
    },
    {
      "id": 13,
      "name": "India Same Day Delivery",
      "cost": 300.0,
      "selected": false,
      "admin_name": "Same Day (within city only)"
    }
  ]
}
```

---

## Notes

1. The `selected` field indicates which shipping method is currently chosen
2. To change shipping method, use the checkout API with `selected_shipping_rate_id`
3. Shipping costs are added to `order.shipment_total`
4. Multiple shipments (for split orders) will each have their own shipping rates

