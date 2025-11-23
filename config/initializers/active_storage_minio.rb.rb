# frozen_string_literal: true

# Override ActiveStorage to use proxy URLs instead of direct S3/MinIO URLs
# This ensures files are served through Rails, making them accessible from browsers
# even when MinIO is only accessible via internal Docker network

Rails.application.config.to_prepare do
  # Override ActiveStorage::Blob#url to always use proxy URLs
  ActiveStorage::Blob.class_eval do
    def url(expires_in: ActiveStorage.service_urls_expire_in, disposition: :inline, filename: nil, **options)
      # Use Rails proxy URL instead of direct service URL
      # This allows Rails to proxy the request to MinIO internally
      Rails.application.routes.url_helpers.rails_blob_proxy_url(
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
      service.url(key, expires_in: expires_in, disposition: disposition, filename: filename || self.filename.to_s, content_type: content_type, **options)
    end
  end
end
