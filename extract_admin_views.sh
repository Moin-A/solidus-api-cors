#!/bin/bash

# Script to manually extract all Solidus admin views to top level

echo "🚀 Starting Solidus Admin Views Extraction..."

# Step 1: Find the solidus_backend gem path
SOLIDUS_BACKEND_PATH=$(rbenv exec bundle show solidus_backend 2>/dev/null)

if [ -z "$SOLIDUS_BACKEND_PATH" ]; then
    echo "❌ Error: solidus_backend gem not found. Make sure Solidus is installed."
    exit 1
fi

echo "📍 Found solidus_backend at: $SOLIDUS_BACKEND_PATH"

# Step 2: Create the destination directories
echo "📁 Creating directory structure..."

mkdir -p app/views/spree/admin
mkdir -p app/views/layouts/spree/admin
mkdir -p app/views/spree/shared
mkdir -p app/assets/stylesheets/spree/admin
mkdir -p app/assets/javascripts/spree/admin

# Step 3: Copy all admin views
echo "📋 Copying admin views..."

# Copy main admin views
if [ -d "$SOLIDUS_BACKEND_PATH/app/views/spree/admin" ]; then
    cp -r "$SOLIDUS_BACKEND_PATH/app/views/spree/admin/"* app/views/spree/admin/
    echo "✅ Copied admin views"
else
    echo "⚠️  Admin views directory not found in gem"
fi

# Copy admin layouts
if [ -d "$SOLIDUS_BACKEND_PATH/app/views/layouts/spree/admin" ]; then
    cp -r "$SOLIDUS_BACKEND_PATH/app/views/layouts/spree/admin/"* app/views/layouts/spree/admin/
    echo "✅ Copied admin layouts"
else
    echo "⚠️  Admin layouts directory not found in gem"
fi

# Copy shared views that admin uses
if [ -d "$SOLIDUS_BACKEND_PATH/app/views/spree/shared" ]; then
    cp -r "$SOLIDUS_BACKEND_PATH/app/views/spree/shared/"* app/views/spree/shared/
    echo "✅ Copied shared views"
fi

# Step 4: Copy admin assets (optional)
echo "🎨 Copying admin assets..."

if [ -d "$SOLIDUS_BACKEND_PATH/app/assets/stylesheets/spree/backend" ]; then
    cp -r "$SOLIDUS_BACKEND_PATH/app/assets/stylesheets/spree/backend/"* app/assets/stylesheets/spree/admin/
    echo "✅ Copied admin stylesheets"
fi

if [ -d "$SOLIDUS_BACKEND_PATH/app/assets/javascripts/spree/backend" ]; then
    cp -r "$SOLIDUS_BACKEND_PATH/app/assets/javascripts/spree/backend/"* app/assets/javascripts/spree/admin/
    echo "✅ Copied admin javascripts"
fi

# Step 5: Create a backup list of copied files
echo "📝 Creating file inventory..."
find app/views/spree/admin -name "*.erb" > admin_views_inventory.txt
find app/views/layouts/spree/admin -name "*.erb" >> admin_views_inventory.txt
echo "✅ File inventory saved to admin_views_inventory.txt"

# Step 6: Display summary
echo ""
echo "🎉 Admin Views Extraction Complete!"
echo ""
echo "📊 Summary:"
echo "- Admin views: $(find app/views/spree/admin -name "*.erb" | wc -l) files"
echo "- Layout views: $(find app/views/layouts/spree/admin -name "*.erb" | wc -l) files"
echo "- Shared views: $(find app/views/spree/shared -name "*.erb" | wc -l) files"
echo ""
echo "📂 Views are now available in:"
echo "   - app/views/spree/admin/"
echo "   - app/views/layouts/spree/admin/"
echo "   - app/views/spree/shared/"
echo ""
echo "🔧 Next steps:"
echo "   1. Customize the views as needed"
echo "   2. Test your admin interface"
echo "   3. Add the views to version control"
echo ""

# Step 7: Create a simple customization example
echo "💡 Creating customization example..."

cat > app/views/spree/admin/shared/_header.html.erb << 'EOF'
<!-- Custom Admin Header -->
<div class="custom-admin-header" style="background: #2c3e50; color: white; padding: 1rem;">
  <h1>🛒 Custom Solidus Admin</h1>
  <div class="admin-nav">
    <%= link_to "Dashboard", spree.admin_path, class: "nav-link" %>
    <%= link_to "Products", spree.admin_products_path, class: "nav-link" %>
    <%= link_to "Orders", spree.admin_orders_path, class: "nav-link" %>
    <%= link_to "Users", spree.admin_users_path, class: "nav-link" %>
    <%= link_to "Settings", spree.admin_general_settings_path, class: "nav-link" %>
  </div>
</div>

<style>
.custom-admin-header .nav-link {
  color: #ecf0f1;
  text-decoration: none;
  margin-right: 1rem;
  padding: 0.5rem;
}

.custom-admin-header .nav-link:hover {
  background: rgba(255,255,255,0.1);
  border-radius: 4px;
}
</style>
EOF

echo "✅ Created example customization in app/views/spree/admin/shared/_header.html.erb"
echo ""
echo "🎯 You can now customize any admin view by editing the files in app/views/spree/admin/"ou