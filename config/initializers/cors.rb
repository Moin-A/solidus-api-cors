# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Add your frontend URLs here
    origins "http://127.0.0.1:3001"

    # Configure the resources for your API
    resource "*",  # Adjust to match your API routes
      headers: :any,    # Allow all headers
      methods: [:get, :post, :put, :patch, :delete, :options, :head, :options],
      credentials: true,  # Allow credentials
      max_age: 86400      # Cache preflight response for 1 day
  end
end 