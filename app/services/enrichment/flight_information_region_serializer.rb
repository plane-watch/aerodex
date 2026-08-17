# frozen_string_literal: true

module Enrichment
  # Serialises a FlightInformationRegion into the shallow object embedded in an
  # airport response. Returns nil when the airport has no region.
  class FlightInformationRegionSerializer
    # @param region [FlightInformationRegion, nil]
    # @return [Hash, nil]
    def self.call(region)
      return nil if region.nil?

      {
        icao_code: region.icao_code,
        region: region.region
      }
    end
  end
end
