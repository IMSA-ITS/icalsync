module Aco
  require 'icalendar'

  class ::Icalendar::Event
    def to_gcal
      raise 'Not implemeted'
    end
  end

  class ::Icalendar::Values::Uri
    def initialize(v, params = {})
      begin
        parsed = URI.parse v
      rescue
        v
      end
      super parsed, params
    end
  end
end
