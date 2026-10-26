# frozen_string_literal: true

require 'csv'

module Processors
  module Runway
    # Processor for importing runway data from OurAirports.com
    #
    # OurAirports provides comprehensive runway data with detailed
    # information for both runway ends.
    #
    # @see https://ourairports.com/data/
    class OurAirports < Processors::Base
      DEFAULT_URL = 'https://davidmegginson.github.io/ourairports-data/runways.csv'

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Runway::OurAirportsRunwaySource.transaction do
            csv.each do |row|
              result = import_row(row, batch_import_timestamp)
              import_errors << result[:error] if result[:error]
              records_processed += 1
              progress_bar.increment!
            end
          end

          new_import_report(import_errors, records_processed)

          import_errors.empty? || import_errors
        end

        private

        def import_row(row, import_timestamp)
          airport_ident = row['airport_ident']&.strip
          le_ident = row['le_ident']&.strip

          return { skipped: true, reason: 'No airport_ident' } if airport_ident.blank?

          # Find or create by the unique combination
          record = Source::Runway::OurAirportsRunwaySource.find_or_initialize_by(
            airport_ident: airport_ident,
            le_ident: le_ident
          )

          record.assign_attributes(
            # Dimensions
            length_ft: parse_decimal(row['length_ft']),
            width_ft: parse_decimal(row['width_ft']),
            surface: row['surface']&.strip,
            lighted: row['lighted'] == '1',
            closed: row['closed'] == '1',

            # Low-end runway data
            le_ident: le_ident,
            le_latitude: parse_decimal(row['le_latitude_deg']),
            le_longitude: parse_decimal(row['le_longitude_deg']),
            le_elevation_ft: parse_decimal(row['le_elevation_ft']),
            le_heading_deg: parse_decimal(row['le_heading_degT']),
            le_displaced_threshold_ft: parse_decimal(row['le_displaced_threshold_ft']),

            # High-end runway data
            he_ident: row['he_ident']&.strip,
            he_latitude: parse_decimal(row['he_latitude_deg']),
            he_longitude: parse_decimal(row['he_longitude_deg']),
            he_elevation_ft: parse_decimal(row['he_elevation_ft']),
            he_heading_deg: parse_decimal(row['he_heading_degT']),
            he_displaced_threshold_ft: parse_decimal(row['he_displaced_threshold_ft']),

            import_date: import_timestamp,
            data: {
              'ourairports_id' => row['id'],
              'airport_ref' => row['airport_ref']
            }
          )

          if record.save
            { runway: record }
          else
            {
              error: {
                airport_ident: airport_ident,
                le_ident: le_ident,
                errors: record.errors.full_messages
              }
            }
          end
        end

        def parse_decimal(value)
          return nil if value.blank?

          BigDecimal(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
