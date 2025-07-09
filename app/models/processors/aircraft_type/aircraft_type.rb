module Processors
  module AircraftType
    class AircraftType < Processors::Base
      def self.combine_sources
        Source::AircraftType::CfappsICAOIntAircraftTypeSource.all.each do |source|
          manufacturer = ::Manufacturer.find_by(icao_code: source.manufacturer)
          record = ::AircraftType.find_or_initialize_by(
            type_code: source.type_code,
            name: source.name,
            manufacturer: manufacturer
          )
          record.wtc = source.wtc
          record.name = source.name
          record.engines = source.engines
          record.engine_type = source.engine_type
          if record.valid?
            record.save!
          else
            puts "Invalid record: #{record.errors.full_messages.join(', ')}"
          end
        end
      end
    end
  end
end
