# frozen_string_literal: true

module Enrichment
  # Serialises a Route into the v2.enrich.routes response body's `route` object.
  # Segments are ordered by their `order` column and embed the lean
  # airport_summary (no runways) plus the scheduled times. Times are formatted as
  # HH:MM:SS strings (the underlying column is a time-of-day, not a full datetime).
  class RouteSerializer
    TIME_FORMAT = '%H:%M:%S'

    # @param route [Route]
    # @return [Hash]
    def self.call(route)
      {
        callsign: route.call_sign,
        operator: OperatorSerializer.call(route.operator),
        segments: route.route_segments.sort_by(&:order).map { |segment| segment_hash(segment) }
      }
    end

    # @param segment [RouteSegment]
    # @return [Hash]
    def self.segment_hash(segment)
      {
        order: segment.order,
        departing_time: segment.departing_time&.strftime(TIME_FORMAT),
        arrival_time: segment.arrival_time&.strftime(TIME_FORMAT),
        airport: AirportSummarySerializer.call(segment.airport)
      }
    end
    private_class_method :segment_hash
  end
end
