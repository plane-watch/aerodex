# frozen_string_literal: true

module Enrichment
  # Serialises an Airport into the v2.enrich.airports response body's `airport`
  # object, including its runways and (shallow) flight information region. The
  # opt-in provenance block is added by the handler, not here.
  class AirportSerializer
    # @param airport [Airport]
    # @return [Hash]
    def self.call(airport)
      {
        icao_code: airport.icao_code,
        iata_code: airport.iata_code,
        wmo_code: airport.wmo_code,
        name: airport.name,
        city: airport.city,
        latitude: airport.latitude&.to_f,
        longitude: airport.longitude&.to_f,
        altitude: airport.altitude&.to_f,
        timezone: airport.timezone,
        country: CountrySerializer.call(airport.country),
        flight_information_region: FlightInformationRegionSerializer.call(airport.flight_information_region),
        runways: airport.airport_runways.map { |runway| RunwaySerializer.call(runway) }
      }
    end
  end
end
