# frozen_string_literal: true

module Enrichment
  # Serialises an AircraftType into the shared `aircraft_type` object. `category`
  # is the enum label string (e.g. "airplane"); `full_name` uses the model's
  # existing helper (manufacturer name + type name).
  class AircraftTypeSerializer
    # @param type [AircraftType, nil]
    # @return [Hash, nil]
    def self.call(type)
      return nil if type.nil?

      {
        type_code: type.type_code,
        name: type.name,
        full_name: type.full_name,
        category: type.category,
        wtc: type.wtc,
        engines: type.engines,
        engine_type: type.engine_type,
        manufacturer: ManufacturerSerializer.call(type.manufacturer)
      }
    end
  end
end
