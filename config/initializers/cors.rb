# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Add your frontend URLs here
    # In production, allow the domain and IP; in development, allow localhost
    if ENV["DOMAIN"]
      origins_list = [
        "https://#{ENV["DOMAIN"]}",
        "http://#{ENV["DOMAIN"]}"
      ]
      # Also allow EC2 IP address (in case requests come from IP)
      if ENV["EC2_IP"]
        origins_list << "http://#{ENV["EC2_IP"]}"
        origins_list << "https://#{ENV["EC2_IP"]}"
      end
      origins(*origins_list)
    else
      origins "http://127.0.0.1:3001"
    end

    # Configure the resources for your API
    resource "*",  # Adjust to match your API routes
      headers: :any,    # Allow all headers
      methods: [:get, :post, :put, :patch, :delete, :options, :head, :options],
      credentials: true,  # Allow credentials
      max_age: 86400      # Cache preflight response for 1 day
  end
end 