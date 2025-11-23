# frozen_string_literal: true

# Override ActiveStorage to use proxy URLs instead of direct S3/MinIO URLs
# This ensures files are served through Rails, making them accessible from browsers
# even when MinIO is only accessible via internal Docker network

Rails.application.config.after_initialize do
  # Override ActiveStorage::Blob#url to always use proxy URLs
  # Using after_initialize ensures routes are loaded
  ActiveStorage::Blob.class_eval do
    alias_method :original_url, :url unless method_defined?(:original_url)
    
    def url(expires_in: ActiveStorage.service_urls_expire_in, disposition: :inline, filename: nil, **options)
      # Use Rails proxy URL instead of direct service URL
      # Use rails_service_blob_proxy_url to explicitly use the proxy route
      # This ensures files are served through Rails, proxying to MinIO internally
      begin
        proxy_url = Rails.application.routes.url_helpers.rails_service_blob_proxy_url(
          self,
          only_path: false,
          host: Rails.application.config.action_mailer.default_url_options&.dig(:host) ||
                (Rails.env.production? ? ENV.fetch('DOMAIN', 'thestorefront.co.in') : 'localhost'),
          protocol: Rails.env.production? ? 'https' : 'http'
        )
        Rails.logger.debug "ActiveStorage: Generated proxy URL for blob #{id}: #{proxy_url}"
        proxy_url
      rescue => e
        Rails.logger.error "ActiveStorage proxy URL generation failed: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        # Fallback to direct service URL on error
        # Ensure filename is properly wrapped if it's a string
        fallback_filename = filename || self.filename
        fallback_filename = ActiveStorage::Filename.wrap(fallback_filename) if fallback_filename.is_a?(String)
        Rails.logger.warn "ActiveStorage: Falling back to direct service URL for blob #{id}"
        service.url(key, expires_in: expires_in, disposition: disposition, filename: fallback_filename, content_type: content_type, **options)
      end
    end
  end
  
  # Also override ActiveStorage::Variant#url to use proxy
  if defined?(ActiveStorage::Variant)
    ActiveStorage::Variant.class_eval do
      alias_method :original_url, :url unless method_defined?(:original_url)
      
      def url(expires_in: ActiveStorage.service_urls_expire_in, disposition: :inline, filename: nil, **options)
        # Variants should also use proxy URLs
        blob.url(expires_in: expires_in, disposition: disposition, filename: filename, **options)
      end
    end
  end
  
  Rails.logger.info "ActiveStorage MinIO proxy override loaded successfully"
end
