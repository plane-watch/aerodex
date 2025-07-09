require 'csv'

module Processors
  module Country
    class OpenTravel < Processors::Base
      @transform_data = {
        'iso_2char_code' => {
          function: ->(value) { value&.strip },
          field: 'iso_2char_code',
        },
        'iso_3char_code' => {
          function: ->(value) { value&.strip },
          field: 'iso_3char_code',
        },
        'iso_num_code' => {
          function: ->(value) { value&.strip },
          field: 'iso_num_code',
        },
        'name' => {
          function: ->(value) { value&.strip },
          field: 'name',
        },
        'cptl' => {
          function: ->(value) { value&.strip },
          field: 'capital',
        }
      }

      DEFAULT_URL = 'https://raw.githubusercontent.com/opentraveldata/opentraveldata/master/opentraveldata/optd_countries.csv'

      def self.import(url = DEFAULT_URL)
        csv_data = get_source_from_url(url)
        return false if csv_data.nil?

        # liberal parsing is needed for nested quotes inside fields
        csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8', col_sep: '^')

        import_errors = []

        Source::Country::OpenTravelCountrySource.transaction do
          csv&.each do |row|
            attributes = {}
            row.headers.each do |key|
              transformed_data = transform_field(key, row[key])
              next if transformed_data.nil?

              attributes[transformed_data[:key]] = transformed_data[:value]
            end

            puts attributes.inspect

            unless attributes['name'].present? && attributes['iso_2char_code'].present? && attributes['iso_3char_code'].present?
              next
            end

            record = Source::Country::OpenTravelCountrySource.find_or_initialize_by(iso_2char_code: attributes['iso_2char_code'])
            record.iso_2char_code = attributes['iso_2char_code']
            record.iso_3char_code = attributes['iso_3char_code']
            record.iso_num_code = attributes['iso_num_code']
            record.name = attributes['name']
            record.capital = attributes['capital']
            record.import_date = Date.today
            record.save!
          end
        end
      end
    end
  end
end
