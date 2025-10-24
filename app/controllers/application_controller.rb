class ApplicationController < ActionController::Base
      def paginate(resource)
        resource.page(params[:page]).per(params[:per_page] || default_per_page)
      end

      def default_per_page
        Kaminari.config.default_per_page
      end
end
