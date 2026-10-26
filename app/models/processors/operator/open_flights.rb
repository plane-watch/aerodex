# frozen_string_literal: true

require 'csv'

module Processors
  module Operator
    # Processor for importing airline/operator data from OpenFlights.org
    #
    # OpenFlights provides airline data in a headerless CSV format with 8 columns.
    # Data is from January 2012 vintage but includes callsigns which are valuable.
    #
    # @see https://openflights.org/data
    class OpenFlights < Processors::Base
      DEFAULT_URL = 'https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat'

      # CSV column indices (0-based) - OpenFlights uses headerless CSV
      COLUMNS = {
        id: 0,
        name: 1,
        alias: 2,
        iata_code: 3,
        icao_code: 4,
        callsign: 5,
        country: 6,
        active: 7
      }.freeze

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          # OpenFlights uses headerless CSV
          csv = CSV.parse(csv_data, headers: false, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Operator::OpenFlightsOperatorSource.transaction do
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
          icao_code = clean_code(row[COLUMNS[:icao_code]])
          iata_code = clean_code(row[COLUMNS[:iata_code]])
          name = normalise_name(row[COLUMNS[:name]])

          # Skip entries without a name
          return { skipped: true, reason: 'No name' } if name.blank?

          # Skip entries without either code
          return { skipped: true, reason: 'No ICAO or IATA code' } if icao_code.blank? && iata_code.blank?

          # Find existing record or create new one
          record = find_or_initialize_record(icao_code, iata_code, name)

          record.assign_attributes(
            name: name,
            icao_code: icao_code,
            iata_code: iata_code,
            import_date: import_timestamp,
            data: build_data_hash(row)
          )

          if record.save
            { operator: record }
          else
            { error: { name: name, icao: icao_code, iata: iata_code, errors: record.errors.full_messages } }
          end
        end

        def find_or_initialize_record(icao_code, iata_code, name)
          # Prefer to match by ICAO code first
          if icao_code.present?
            Source::Operator::OpenFlightsOperatorSource.find_or_initialize_by(icao_code: icao_code)
          else
            # Fall back to IATA + name for disambiguation
            Source::Operator::OpenFlightsOperatorSource.find_or_initialize_by(
              iata_code: iata_code,
              name: name
            )
          end
        end

        # Cleans airport/airline codes - OpenFlights uses \N for null values
        def clean_code(value)
          return nil if value.blank? || value == '\\N' || value == '-'

          cleaned = value.strip
          cleaned.present? ? cleaned : nil
        end

        # Normalises operator name (removes excess whitespace, handles encoding)
        def normalise_name(value)
          return nil if value.blank? || value == '\\N'

          value.strip.gsub(/\s+/, ' ')
        end

        def build_data_hash(row)
          {
            'openflights_id' => row[COLUMNS[:id]],
            'alias' => clean_value(row[COLUMNS[:alias]]),
            'callsign' => clean_value(row[COLUMNS[:callsign]]),
            'country' => clean_value(row[COLUMNS[:country]]),
            'active' => row[COLUMNS[:active]]
          }.compact
        end

        def clean_value(value)
          return nil if value.blank? || value == '\\N'

          value.strip.presence
        end
      end
    end
  end
end
