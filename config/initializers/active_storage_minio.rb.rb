# frozen_string_literal: true

# Override ActiveStorage S3 service to use proxy URLs instead of direct S3 URLs
# This ensures files are served through Rails, making them accessible from browsers
# even when MinIO is only accessible via internal Docker network

Rails.application.config.to_prepare do
  # Wait for ActiveStorage to be fully loaded
  if defined?(ActiveStorage::Service::S3Service)
    ActiveStorage::Service::S3Service.class_eval do
      def url(key, expires_in:, filename:, disposition:, content_type:)
        # Find the blob by key
        blob = ActiveStorage::Blob.find_by_key(key)
        return super unless blob # Fallback to direct URL if blob not found
        
        # Use Rails proxy URL instead of direct S3 URL
        # This allows Rails to proxy the request to MinIO internally
        Rails.application.routes.url_helpers.rails_blob_proxy_url(
          blob,
          only_path: false,
          host: Rails.application.config.action_mailer.default_url_options&.dig(:host) ||
                (Rails.env.production? ? ENV.fetch('DOMAIN', 'thestorefront.co.in') : 'localhost'),
          protocol: Rails.env.production? ? 'https' : 'http'
        )
      rescue => e
        Rails.logger.error "ActiveStorage proxy URL generation failed: #{e.message}"
        # Fallback to direct URL on error
        super
      end
    end
  end
end
