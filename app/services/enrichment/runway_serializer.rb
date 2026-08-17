# frozen_string_literal: true

module Enrichment
  # Serialises an AirportRunway. The `heading`, `length` and `width` columns are
  # stored as unit-less decimals (the canonical table does not record units);
  # they are converted to floats so they serialise as JSON numbers rather than
  # strings.
  class RunwaySerializer
    # @param runway [AirportRunway]
    # @return [Hash]
    def self.call(runway)
      {
        name: runway.runway_name,
        le_ident: runway.le_ident,
        he_ident: runway.he_ident,
        heading: runway.heading&.to_f,
        length: runway.length&.to_f,
        width: runway.width&.to_f,
        surface: runway.surface,
        lighted: runway.lighted,
        closed: runway.closed
      }
    end
  end
end
