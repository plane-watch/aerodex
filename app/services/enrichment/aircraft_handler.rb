# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.aircraft: looks up an aircraft by ICAO Mode-S hex and
  # returns its serialised record, optionally with a provenance block.
  class AircraftHandler < Handler
    private

    def handle(request)
      icao = request[:icao]
      raise BadRequestError, 'icao is required' if icao.blank?

      aircraft = AircraftQuery.call(icao)
      return { found: false } unless aircraft

      response = { found: true, aircraft: AircraftSerializer.call(aircraft) }
      response[:provenance] = ProvenanceSerializer.call(aircraft) if include?(request, 'provenance')
      response
    end
  end
end
