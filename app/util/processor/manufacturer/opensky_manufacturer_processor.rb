require 'csv'

module Processor
  module Manufacturer
    class OpenskyManufacturerProcessor < Processor::ProcessorBase
      @transform_data = {
        'Code' => {
          function: ->(value) { value&.strip },
          field: 'icao_code',
        },
        'Name' => {
          function: ->(value) { value&.strip },
          field: 'name',
        }
      }

      DEFAULT_URL = 'https://opensky-network.org/datasets/metadata/doc8643Manufacturers.csv'

      def self.import(url = DEFAULT_URL)
        csv_data = get_source_from_url(url)
        return false if csv_data.nil?

        # liberal parsing is needed for nested quotes inside fields
        csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8', col_sep: ',', liberal_parsing: true)

        import_errors = []

        Source::Manufacturer::OpenskyManufacturerSource.transaction do
          csv&.each do |row|
            attributes = {}

            row.headers.each do |key|
              transformed_data = transform_field(key, row[key])
              next if transformed_data.nil?

              attributes[transformed_data[:key]] = transformed_data[:value]
            end

            country = nil

            if attributes['name'].present? && attributes['icao_code'].present?
              record = Source::Manufacturer::OpenskyManufacturerSource.find_or_initialize_by(icao_code: attributes['icao_code'])
              record.icao_code = attributes['icao_code']
              record.name = attributes['name']
              record.import_date = Date.today
              record.save!
            end
          end
        end
      end
    end
  end
end
