# frozen_string_literal: true

module Enrichment
  # Looks up a single Route by callsign, case-insensitively, eager loading the
  # operator and the ordered segments with their airports for the route
  # serializer.
  class RouteQuery
    # @param callsign [String, nil]
    # @return [Route, nil]
    def self.call(callsign)
      return nil if callsign.blank?

      Route
        .includes(
          { operator: %i[country parent_operator] },
          { route_segments: { airport: :country } }
        )
        .where('UPPER(call_sign) = ?', callsign.to_s.upcase)
        .first
    end
  end
end
