# frozen_string_literal: true

require 'csv'

module Processors
  module Operator
    class VRSData < Processors::Operator::Base
      @transform_data = {
        'Name' => {
          function: ->(value) { normalise_name(value) },
          field: 'name'
        },
        'ICAO' => {
          function: ->(value) { value.blank? ? nil : value.strip },
          field: 'icao_code'
        },
        'IATA' => {
          function: ->(value) { value&.strip },
          field: 'iata_code'
        },
        'PositioningFlightPattern' => {
          function: ->(value) { value.blank? ? nil : value.strip },
          field: 'positioning_callsign_pattern'
        },
        'CharterFlightPattern' => {
          function: ->(value) { value.blank? ? nil : value.strip },
          field: 'charter_callsign_pattern'
        }
      }

      DEFAULT_URL = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/airlines/schema-01/airlines.csv'

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)

          csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8')

          batch_import_timestamp = DateTime.now

          import_errors = []
          records_processed = 0

          csv&.each do |row|
            attributes = {}
            row.headers.each do |key|
              transformed_data = transform_field(key, row[key])
              next if transformed_data.nil?

              attributes[transformed_data[:key]] = transformed_data[:value]
            end

            search_params = attributes.dup.slice(*%w[icao_code iata_code name])
            search_params.except!(*%w[name iata_code]) if search_params['icao_code']

            record = Source::Operator::VRSDataOperatorSource.find_unique_operator(search_params).first_or_initialize

            record.attributes = {
              icao_code: attributes['icao_code'],
              iata_code: attributes['iata_code'],
              name: attributes['name'],
              data: attributes
            }
            record.import_date = batch_import_timestamp if record.new_record? || record.changed?
            records_processed += 1

            # if record.valid?
            record.save!
            # else
            #   puts record.errors
            #   import_errors.append(record.errors)
            # end
          end

          new_import_report(import_errors, records_processed)
        end
      end
    end
  end
end