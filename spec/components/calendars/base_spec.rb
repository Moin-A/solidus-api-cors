require 'rails_helper'
require 'view_component/test_helpers'

RSpec.describe Calendars::Base, type: :component do
  include ViewComponent::TestHelpers

  describe '#initialize' do
    it 'initializes with today\'s date by default' do
      calendar = Calendars::Base.new
      expect(calendar.instance_variable_get(:@date)).to eq(Date.today)
    end
  end

  describe 'attaching view context manually' do
    it 'allows accessing helpers when view context is attached' do
      calendar = Calendars::Base.new
      
      # Attach the view context manually
      # This allows testing methods that use helpers without rendering the whole component
      calendar.instance_variable_set(:@view_context, view_context)
      
      # Verify that we can call a method that uses a helper (time_tag)
      # This would raise an error if view_context was not attached
      expect(calendar.formatted_date).to include(Date.today.year.to_s)
    end
  end
end
