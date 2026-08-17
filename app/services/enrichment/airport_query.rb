# frozen_string_literal: true

module Enrichment
  # Looks up a single Airport by ICAO or IATA code, case-insensitively. ICAO
  # takes precedence when both are supplied. Eager loads the country, flight
  # information region and runways for the airport serializer.
  class AirportQuery
    # @param icao [String, nil]
    # @param iata [String, nil]
    # @return [Airport, nil]
    def self.call(icao: nil, iata: nil)
      scope = Airport.includes(:country, :flight_information_region, :airport_runways)

      if icao.present?
        scope.where('UPPER(icao_code) = ?', icao.to_s.upcase).first
      elsif iata.present?
        scope.where('UPPER(iata_code) = ?', iata.to_s.upcase).first
      end
    end
  end
end
