# frozen_string_literal: true

# Kaminari Pagination Configuration
# https://github.com/kaminari/kaminari

Kaminari.configure do |config|
  # Default number of items per page
  # Default: 25
  config.default_per_page = 6
  
  # Maximum number of items per page (prevents requesting too many items)
  # Default: nil (no limit)
  config.max_per_page = 100
  
  # Maximum number of pages to display in pagination
  # Default: 7
  # config.max_pages = nil
  
  # The default distance from the current page to the outer window
  # Default: 0
  # config.outer_window = 0
  
  # The default distance from the current page to the left/right window
  # Default: 4
  # config.left = 4
  # config.right = 4
  
  # Parameter name for page number
  # Default: :page
  # config.param_name = :page
  
  # Parameter name for per_page
  # Default: :per_page
  # config.per_page_param_name = :per_page
  
  # Page method name
  # Default: :page
  # config.page_method_name = :page
end

