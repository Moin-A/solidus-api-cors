Rails.application.routes.draw do
  mount SolidusAdmin::Engine, at: '/admin', constraints: ->(req) {
    req.cookies['solidus_admin'] != 'false' &&
    req.params['solidus_admin'] != 'false'
  }
  mount SolidusPaypalCommercePlatform::Engine, at: '/solidus_paypal_commerce_platform'
  scope(path: '/') { draw :storefront }

  Spree::Core::Engine.routes.draw do
    namespace :admin do
      resource :general_settings, only: [:show, :edit, :update] 
        post 'shipments/:shipment_number/mark_ready', to: 'orders#mark_ready', as: :mark_shipment_ready
        post 'shipments/:shipment_number/ship', to: 'orders#ship_shipment', as: :ship_shipment
    end
  end
  # This line mounts Solidus's routes at the root of your application.
  #
  # Unless you manually picked only a subset of Solidus components, this will mount routes for:
  #   - solidus_backend
  #   - solidus_api
  # This means, any requests to URLs such as /admin/products, will go to Spree::Admin::ProductsController.
  #
  # If you are using the Starter Frontend as your frontend, be aware that all the storefront routes are defined
  # separately in this file and are not part of the Solidus::Core::Engine engine.
  #
  # If you would like to change where this engine is mounted, simply change the :at option to something different.
  # We ask that you don't use the :as option here, as Solidus relies on it being the default of "spree"
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Comprehensive API routes for frontend
  namespace :api do
    # Authentication
    post 'login', to: 'auth#login'
    post 'register', to: 'auth#register'
    post 'logout', to: 'auth#logout'
    resources :stores, only: [:show]
    
    # Test endpoint
    get 'test', to: 'test#index'
    
    # Products
    resources :products, only: [:index, :show] do
      member do
        get 'variants'
        get 'related'
      end
      collection do
        get 'top_rated'
      end
    end
    
    # Variants
    resources :variants, only: [:index, :show] do
      collection do
        get 'by_product/:product_id', to: 'variants#by_product'
      end
    end
    
    # Categories/Taxons
    resources :categories, only: [:index, :show] do
      member do
        get 'products'
        get  'taxons'
      end
    end

    namespace :auth do
      get 'verification/confirm_email', to: 'verification#confirm_email'
      post 'verification/verify_phone', to: 'verification#verify_phone'
      post 'verification/resend_confirmation', to: 'verification#resend_confirmation'
      post 'verification/resend_phone', to: 'verification#resend_phone'
      post '/password/change', to: 'password#update', as: :change_password
      post '/password/recover', to: 'password#create', as: :reset_password
    end

    
    # Cart operations
    get 'cart', to: 'cart#show'
    post 'cart/add_item', to: 'cart#add_item'
    put 'cart/update_item/:line_item_id', to: 'cart#update_item'
    delete 'cart/remove_item/:line_item_id', to: 'cart#remove_item'
    delete 'cart/empty', to: 'cart#empty'
    get 'cart/checkout', to: 'cart#checkout'
    
    # Orders
    resources :orders, only: [:index, :show, :create, :update, :destroy] do
      member do
        get 'available_shipping_methods'
        post 'review_product'
      end
    end
    
    # Checkouts (under spree namespace)
    namespace :spree do
      namespace :api do
        resources :checkouts, only: [] do
          member do
            put :next
            put :advance
            put :update
            put :complete
          end
        end
      end
    end
    
    # User profile and addresses
    get 'profile', to: 'users#profile'
    get 'addresses', to: 'users#addresses'
    post 'addresses', to: 'users#create_address'
    
    resources :users, only: [:show, :update]

    
    # Search
    get 'search/products', to: 'search#products'
    get 'search/suggestions', to: 'search#suggestions'
    get 'search/elasticsearch', to: 'search#elasticsearch_products'
    
    # Additional e-commerce endpoints
    get 'countries', to: 'countries#index'
    get 'states/:country_id', to: 'states#index'
    get 'payment_methods', to: 'payment_methods#index'
    get 'shipping_methods', to: 'shipping_methods#index'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  mount Spree::Core::Engine, at: '/'
  # Defines the root path route ("/")
  # root "posts#index"
end
