module Processors
  module AircraftType
    class CfappsICAOInt < Processors::Base
      def self.import
        @transform_data = {
          'Designator' => {
            function: ->(value) { value&.strip },
            field: 'type_code',
          },
          'ModelFullName' => {
            function: ->(value) { value&.strip },
            field: 'name',
          },
          'ManufacturerCode' => {
            function: ->(value) { value&.strip },
            field: 'manufacturer',
          },
          'WTC' => {
            function: ->(value) { value&.strip },
            field: 'wtc',
          },
          'EngineCount' => {
            function: ->(value) { value&.strip.to_i },
            field: 'engines',
          },
          'EngineType' => {
            function: ->(value) { value&.strip },
            field: 'engine_type',
          },
        }

        default_url = 'https://www4.icao.int/doc8643/External/AircraftTypes'

        source_data = get_source_from_url(default_url, 'POST')

        json_data = JSON.parse(source_data) # results in an array of hashes

        json_data.each do |entry|
          transformed_attrs = {}
          entry.each do |key, value|
            transformed_data = transform_field(key, value)
            next if transformed_data.nil?

            transformed_attrs[transformed_data[:key]] = transformed_data[:value]
          end

          record = Source::AircraftType::CfappsICAOIntAircraftTypeSource.find_or_initialize_by(
            type_code: transformed_attrs['type_code'],
            name: transformed_attrs['name'],
            manufacturer: transformed_attrs['manufacturer'],
            wtc: transformed_attrs['wtc'],
            engines: transformed_attrs['engines'],
            engine_type: transformed_attrs['engine_type']
          )
          record.save!
        end
      end
    end
  end
end
