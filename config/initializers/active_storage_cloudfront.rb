# frozen_string_literal: true

# Configure Active Storage to use CloudFront CDN instead of direct S3 URLs
# This ensures all asset URLs use CloudFront domain for better performance
if Rails.env.production? && Rails.application.config.active_storage.service == :amazon
  # Wait for ActiveStorage::Blob to load, then modify S3Service
  ActiveSupport.on_load(:active_storage_blob) do
    require 'active_storage/service/s3_service'
    
    # Override the url method to return CloudFront URLs instead of S3 URLs
    ActiveStorage::Service::S3Service.class_eval do
      alias_method :original_url, :url
      
      def url(key, expires_in:, filename:, disposition:, content_type:)
        # Replace S3 URL with CloudFront URL
        cloudfront_base = ENV.fetch("CLOUDFRONT_URL", "https://d3687nk8qb4e0v.cloudfront.net").chomp("/")
        "#{cloudfront_base}/#{key}"
      end
    end
  end
  
  # Override attachment_url method in ActiveStorageAdapter to use CloudFront
  # Why to_prepare instead of after_initialize?
  # - In development, Rails reloads code on every request
  # - If we use after_initialize, our monkey patch gets lost after first reload
  # - to_prepare runs after EVERY code reload, ensuring our patch survives
  # - In production, to_prepare only runs once (no performance penalty)
  #
  # Why module_eval instead of class_eval?
  # - Spree::ActiveStorageAdapter is a MODULE, not a class
  # - module_eval is semantically correct for modules
  # - (Note: class_eval also works on modules, but module_eval is clearer)
  Rails.application.config.to_prepare do
    Spree::ActiveStorageAdapter.module_eval do
      def attachment_url
        return nil unless attachment.attached?
        
        # Use CloudFront URL directly instead of going through Rails routes
        cloudfront_base = ENV.fetch("CLOUDFRONT_URL", "https://d3687nk8qb4e0v.cloudfront.net").chomp("/")
        "#{cloudfront_base}/#{attachment.blob.key}"
      end
    end
  end
end

