# app/controllers/spree/admin/stores_controller_decorator.rb
module Spree
  module Admin
    StoresController.class_eval do
      private

      def store_params
        params.require(:store).permit(
          :name, :url, :mail_from_address, :meta_description,
          :meta_keywords, :seo_title, :default_currency,
          :code, :default, :available_locales, :bcc_email,
          :cart_tax_country_iso,
          # Add hero image permissions
          :hero_image, :remove_hero_image
        )
      end
    end
  end
end