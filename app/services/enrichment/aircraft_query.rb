# frozen_string_literal: true

module Enrichment
  # Looks up a single Aircraft by ICAO Mode-S hex, case-insensitively, eager
  # loading every association the aircraft serializer touches to avoid N+1
  # queries.
  class AircraftQuery
    # @param icao [String, nil]
    # @return [Aircraft, nil]
    def self.call(icao)
      return nil if icao.blank?

      Aircraft
        .includes(
          :registration_country,
          { operator: %i[country parent_operator] },
          { aircraft_type: { manufacturer: :country } }
        )
        .where('UPPER(icao) = ?', icao.to_s.upcase)
        .first
    end
  end
end
