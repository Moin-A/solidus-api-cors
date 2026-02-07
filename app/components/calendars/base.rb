module Calendars
  class Base < ViewComponent::Base
    def initialize
      @date = Date.today
    end

    # Example method that relies on view_context (via helpers)
    def formatted_date
      helpers.time_tag(@date)
    end
  end
end
