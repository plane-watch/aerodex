# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.airport: looks up an airport by ICAO or IATA code and
  # returns its serialised record (including runways), optionally with a
  # provenance block.
  class AirportHandler < Handler
    private

    def handle(request)
      icao = request[:icao]
      iata = request[:iata]
      raise BadRequestError, 'icao or iata is required' if icao.blank? && iata.blank?

      airport = AirportQuery.call(icao: icao, iata: iata)
      return { found: false } unless airport

      response = { found: true, airport: AirportSerializer.call(airport) }
      response[:provenance] = ProvenanceSerializer.call(airport) if include?(request, 'provenance')
      response
    end
  end
end
