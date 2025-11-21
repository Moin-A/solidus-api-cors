# Moving to Production SSL: Checklist

When you obtain a domain and SSL certificates (or use Kamal's auto-SSL with Let's Encrypt), you will need to revert some temporary settings to secure the application.

## 1. Revert `config/environments/production.rb`

Once SSL is active, you must force HTTPS connection to ensure security (cookies, HSTS).

```ruby
# config/environments/production.rb

# CHANGE THIS BACK TO TRUE
# Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
config.force_ssl = true 

# OPTIONAL: Consider setting this back to false for performance if you fix the build process
# Do not fallback to assets pipeline if a precompiled asset is missed.
config.assets.compile = false 
```

## 2. Update `config/deploy.yml`

Update the proxy configuration to use your real domain and enable SSL.

```yaml
# config/deploy.yml

proxy:
  ssl: true             # CHANGE THIS BACK TO TRUE
  host: api.yourdomain.com # Use your real domain
  app_port: 3000
```

## 3. Update CORS (`config/initializers/cors.rb`)

Update the allowed origins to your production frontend domain instead of IP or localhost.

```ruby
# config/initializers/cors.rb

allow do
  origins "https://www.yourdomain.com" # Add your real frontend domain
  # ...
end
```

## 4. DNS Setup

1.  Create an **A Record** for `api.yourdomain.com` pointing to `13.53.125.253`.
2.  Create an **A Record** for `www.yourdomain.com` (frontend) pointing to `13.53.125.253`.

## 5. Asset Precompilation (Recommended)

Ideally, you should fix the SassC error in the `Dockerfile` so you can disable runtime asset compilation (`config.assets.compile = false`). This improves performance.

1.  Uncomment `RUN ... assets:precompile` in `Dockerfile`.
2.  Fix the CSS syntax error (usually in `app/assets/stylesheets` or a gem dependency) or upgrade `sassc-rails`.



