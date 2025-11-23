require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Enable static file serving from the `/public` folder (turn off if using NGINX/Apache for it).
  config.public_file_server.enabled = true

  # Compress CSS using a preprocessor.
  # Explicitly disable CSS compression to prevent SassC from failing on Tailwind's modern CSS syntax
  # We use a No-Op compressor because setting it to nil might not be enough if sassc-rails is present
  config.assets.css_compressor = Class.new { def compress(string); string; end }.new

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  # Assets are precompiled in Dockerfile to avoid SassC errors with Tailwind's modern CSS syntax
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on MinIO (S3-compatible) storage (see config/storage.yml for options).
  config.active_storage.service = :minio
  
  # Use proxy mode to serve files through Rails instead of direct MinIO URLs
  # This ensures URLs are accessible from browsers (Rails proxies to MinIO internally)
  # Files will be served via /rails/active_storage/disk/... URLs
  config.active_storage.variant_processor = :mini_magick
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # Traefik handles SSL termination, so we assume SSL is always present
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to both STDOUT (for Docker/Kamal) and file (for persistent storage)
  # Create log directory if it doesn't exist
  log_dir = Rails.root.join("log")
  FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
  
  # Create a file logger for unformatted logs (raw logs without timestamps/levels)
  file_logger = ActiveSupport::Logger.new(log_dir.join("production"))
  file_logger.level = Logger::DEBUG # More verbose logging to file
  # Use a simple formatter that just outputs the message
  file_logger.formatter = proc do |severity, datetime, progname, msg|
    "#{msg}\n" # Just the message, no formatting
  end
  
  # Create STDOUT logger for Docker/Kamal (formatted with tags)
  stdout_logger = ActiveSupport::Logger.new(STDOUT)
  stdout_logger.formatter = ::Logger::Formatter.new
  stdout_logger = ActiveSupport::TaggedLogging.new(stdout_logger)
  
  # Use a broadcast logger to log to both STDOUT and file
  config.logger = ActiveSupport::BroadcastLogger.new(stdout_logger)
  config.logger.broadcast_to(file_logger)
  
  # Prepend all log lines with the following tags (only affects STDOUT, not file)
  config.log_tags = [ :request_id ]

  # Use debug level for more verbose logging (can be overridden with RAILS_LOG_LEVEL env var)
  # This will show more detailed information including our debug statements
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter     = :resque
  # config.active_job.queue_name_prefix = "solidus_api_production"

  config.action_mailer.perform_caching = false

  # Configure default URL options for email links
  domain = ENV["DOMAIN"] || "thestorefront.co.in"
  config.action_mailer.default_url_options = { host: domain, protocol: "https" }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  domain = ENV["DOMAIN"] || "thestorefront.co.in"
  ec2_ip = ENV["EC2_IP"]
  allowed_hosts = [
    domain,           # Allow requests from thestorefront.co.in
    /.*\.#{domain.gsub('.', '\.')}/ # Allow requests from subdomains
  ]
  # Also allow EC2 IP address (in case requests come with IP in Host header)
  # This can happen if Traefik forwards with IP or if DNS resolves to a different IP
  allowed_hosts << ec2_ip if ec2_ip
  # Allow IP address pattern (for cases where domain resolves to IP)
  allowed_hosts << /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/
  config.hosts = allowed_hosts
  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
