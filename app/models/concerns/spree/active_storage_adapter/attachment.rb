# frozen_string_literal: true

require 'mini_magick'

module Spree
  module ActiveStorageAdapter
    # Decorates ActiveStorage attachment to add methods expected by Solidus'
    # Paperclip-oriented attachment support.
    class Attachment
      delegate_missing_to :@attachment

      attr_reader :attachment

      def initialize(attachment, styles: {})
        @attachment = attachment
        @transformations = styles_to_transformations(styles)
      end

      def exists?
        attached?
      end

      def filename
        blob&.filename.to_s
      end

      def url(style = nil)
        variant_url = variant(style)&.url
        return variant_url if variant_url.present?
        
        # Return fallback URL if variant is nil or URL is nil
        # This prevents "Nil location provided. Can't build URI." errors
        return nil unless attached?
        
        # Try to return the original attachment URL as fallback
        @attachment.url rescue nil
      end

      def variant(style = nil)
        return nil unless attached?
        
        transformation = @transformations[style]
        
        # If no style-specific transformation, use default if dimensions are available
        if transformation.nil?
          return nil if width.nil? || height.nil?
          transformation = default_transformation(width, height)
        end
        
        # Create variant with transformation options
        # Note: saver options like strip are handled by ActiveStorage when using image_processing
        @attachment.variant(transformation).processed
      rescue => e
        Rails.logger.error("Failed to create variant: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        nil
      end

      def height
        metadata[:height]
      end

      def width
        metadata[:width]
      end

      def destroy
        return false unless attached?

        purge
        true
      end

      private

      def metadata
        analyze unless analyzed?

        @attachment.metadata
      rescue ActiveStorage::FileNotFoundError => error
        logger.error("#{error} - Image id: #{attachment.record.id} is corrupted or cannot be found")

        { identified: nil, width: nil, height: nil, analyzed: true }
      end

      def styles_to_transformations(styles)
        styles.transform_values(&method(:imagemagick_to_image_processing_definition))
      end

      def imagemagick_to_image_processing_definition(definition)
        width_height = definition.split('x').map(&:to_i)

        case definition[-1].to_sym
        when :^
          { resize_to_fill: width_height }
        else
          default_transformation(*width_height)
        end
      end

      def default_transformation(width, height)
        { resize_to_limit: [width, height] }
      end
    end
  end
end
