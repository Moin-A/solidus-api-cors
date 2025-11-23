# frozen_string_literal: true

# Override ActiveStorage to use proxy URLs instead of direct S3/MinIO URLs
# This ensures files are served through Rails, making them accessible from browsers
# even when MinIO is only accessible via internal Docker network

Rails.application.config.to_prepare do
  # Override ActiveStorage::Blob#url to always use proxy URLs
  ActiveStorage::Blob.class_eval do
    def url(expires_in: ActiveStorage.service_urls_expire_in, disposition: :inline, filename: nil, **options)
      # Use Rails proxy URL instead of direct service URL
      # Use rails_service_blob_proxy_url to explicitly use the proxy route
      # This ensures files are served through Rails, proxying to MinIO internally
      Rails.application.routes.url_helpers.rails_service_blob_proxy_url(
        self,
        only_path: false,
        host: Rails.application.config.action_mailer.default_url_options&.dig(:host) ||
              (Rails.env.production? ? ENV.fetch('DOMAIN', 'thestorefront.co.in') : 'localhost'),
        protocol: Rails.env.production? ? 'https' : 'http'
      )
    rescue => e
      Rails.logger.error "ActiveStorage proxy URL generation failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      # Fallback to direct service URL on error
      # Ensure filename is properly wrapped if it's a string
      fallback_filename = filename || self.filename
      fallback_filename = ActiveStorage::Filename.wrap(fallback_filename) if fallback_filename.is_a?(String)
      service.url(key, expires_in: expires_in, disposition: disposition, filename: fallback_filename, content_type: content_type, **options)
    end
  end
end
