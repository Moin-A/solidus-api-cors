#!/bin/bash
echo "🧹 Cleaning up and doing fresh Solidus admin views extraction..."

# Find solidus_backend path
SOLIDUS_BACKEND_PATH=$(rbenv exec bundle show solidus_backend 2>/dev/null)
if [ -z "$SOLIDUS_BACKEND_PATH" ]; then
    echo "❌ Error: solidus_backend gem not found"
    exit 1
fi

echo "📍 Found solidus_backend at: $SOLIDUS_BACKEND_PATH"

# Clean up existing custom views
echo "🧹 Cleaning existing custom views..."
rm -rf app/views/spree/layouts/admin.html.erb
rm -rf app/views/spree/admin/shared/
rm -rf app/views/layouts/spree/

# Create only necessary directories
echo "📁 Creating minimal directory structure..."
mkdir -p app/views/spree/admin

# Copy ONLY specific admin views, NOT layouts or shared
echo "📋 Copying only admin controller views..."
if [ -d "$SOLIDUS_BACKEND_PATH/app/views/spree/admin" ]; then
    # Copy admin views but exclude shared and layouts
    find "$SOLIDUS_BACKEND_PATH/app/views/spree/admin" -name "*.erb" -not -path "*/shared/*" | while read file; do
        relative_path=${file#$SOLIDUS_BACKEND_PATH/app/views/}
        target_dir="app/views/$(dirname "$relative_path")"
        mkdir -p "$target_dir"
        cp "$file" "app/views/$relative_path"
        echo "✅ Copied: $relative_path"
    done
fi

# DO NOT copy layouts - let Solidus use its own
echo "⚠️  Skipping layouts - using original Solidus layouts"

# DO NOT copy shared views initially - let Solidus use its own  
echo "⚠️  Skipping shared views - using original Solidus shared views"

echo ""
echo "🎉 Clean extraction complete!"
echo ""
echo "📊 Summary:"
echo "- Admin controller views: $(find app/views/spree/admin -name "*.erb" -not -path "*/shared/*" | wc -l) files"
echo "- Using original Solidus layouts and shared views"
echo ""
echo "🔧 This should restore your sidebar and fix layout issues!"
echo "📂 Only controller-specific views are customized in:"
echo "   - app/views/spree/admin/"
echo ""
echo "🚀 Try accessing your admin now!"