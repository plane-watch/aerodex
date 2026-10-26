# frozen_string_literal: true

module Enrichment
  # Serialises an Airport into the lean `airport_summary` object embedded in
  # route segments. Deliberately omits runways to keep route responses small;
  # full runways are available via the v2.enrich.airports subject.
  class AirportSummarySerializer
    # @param airport [Airport, nil]
    # @return [Hash, nil]
    def self.call(airport)
      return nil if airport.nil?

      {
        icao_code: airport.icao_code,
        iata_code: airport.iata_code,
        name: airport.name,
        city: airport.city,
        latitude: airport.latitude&.to_f,
        longitude: airport.longitude&.to_f,
        altitude: airport.altitude&.to_f,
        timezone: airport.timezone,
        country: CountrySerializer.call(airport.country)
      }
    end
  end
end
