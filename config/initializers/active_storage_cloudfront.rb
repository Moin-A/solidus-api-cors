# frozen_string_literal: true

# Configure Active Storage to use CloudFront CDN instead of direct S3 URLs
# This ensures all asset URLs use CloudFront domain for better performance
if Rails.env.production? && Rails.application.config.active_storage.service == :amazon
  ActiveSupport.on_load(:active_storage_blob) do
    require 'active_storage/service/s3_service'
    
    ActiveStorage::Service::S3Service.class_eval do
      alias_method :original_url, :url
      
      def url(key, expires_in:, filename:, disposition:, content_type:)
        # Use CloudFront URL instead of S3 direct URL
        cloudfront_base = ENV.fetch("CLOUDFRONT_URL", "https://d3687nk8qb4e0v.cloudfront.net").chomp("/")
        "#{cloudfront_base}/#{key}"
      end
    end
  end
end

