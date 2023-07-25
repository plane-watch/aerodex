module DataSource
  class CASA

    CONFIDENCE_MODIFIERS = {
      icao: {
        filter: ->(object) { object.icao =~ /\A7C/ },
        modifier: -> (confidence) { 10 }
      }
    }

    CONFIDENCE_FIELD_MODIFIERS = {
      ## None
      # example_field: {
      #   filter: ->(object) { object.field == 'None' },
      #   modifier: -> (confidence) { 0 }
      # }
    }
  end
end