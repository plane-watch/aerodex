# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.route: looks up a route by callsign and returns its
  # serialised record. Routes do not carry field-level provenance, so the
  # provenance include is not honoured here.
  class RouteHandler < Handler
    private

    def handle(request)
      callsign = request[:callsign]
      raise BadRequestError, 'callsign is required' if callsign.blank?

      route = RouteQuery.call(callsign)
      return { found: false } unless route

      { found: true, route: RouteSerializer.call(route) }
    end
  end
end
