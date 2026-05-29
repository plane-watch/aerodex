# frozen_string_literal: true

module Enrichment
  # Serialises a Manufacturer into the shared `manufacturer` object embedded in
  # an aircraft type. Source/provenance metadata is intentionally excluded.
  class ManufacturerSerializer
    # @param manufacturer [Manufacturer, nil]
    # @return [Hash, nil]
    def self.call(manufacturer)
      return nil if manufacturer.nil?

      {
        name: manufacturer.name,
        icao_code: manufacturer.icao_code,
        alt_names: manufacturer.alt_names || [],
        country: CountrySerializer.call(manufacturer.country)
      }
    end
  end
end
