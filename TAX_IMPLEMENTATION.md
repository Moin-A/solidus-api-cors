Assam GST Setup - Electronics & Clothing
Quick Overview
Setting up GST for an Assam-based e-commerce store selling:

Electronics (18% GST)
Readymade Clothing (12% GST)

All sales are within Assam (intra-state), so only CGST + SGST applies.

GST Rates
1. Electronics - 18% GST
Includes:

Mobile phones & accessories
Laptops & computers
Tablets & iPads
Cameras & photography equipment
Headphones & audio devices
Smart watches & wearables
Gaming consoles

Tax Breakdown:

CGST: 9%
SGST: 9% (Assam)
Total: 18%

Example:
Product: Samsung Galaxy S24 - ₹75,000

CGST @ 9%:       ₹6,750
SGST @ 9%:       ₹6,750
────────────────────────
Total Tax:      ₹13,500
Final Price:    ₹88,500

2. Readymade Clothing - 12% GST
Includes:

Shirts, T-shirts
Jeans, trousers
Dresses, skirts
Jackets, sweaters
Traditional wear (kurtas, sarees)
Sportswear

Tax Breakdown:

CGST: 6%
SGST: 6% (Assam)
Total: 12%

Example:
Product: Denim Jeans - ₹2,000

CGST @ 6%:      ₹120
SGST @ 6%:      ₹120
────────────────────────
Total Tax:      ₹240
Final Price:    ₹2,240

Setup Instructions
Step 1: Run the Setup Script
Option A: Using Rake Task
Create file: lib/tasks/setup_gst.rake
rubynamespace :gst do
  desc "Setup GST rates for Assam"
  task setup: :environment do
    # Copy the code from the first artifact here
  end
end
Run:
bashrake gst:setup