# frozen_string_literal: true

require 'csv'

module Processors
  module AircraftType
    # Processor for importing aircraft type data from OpenFlights.org
    #
    # OpenFlights provides aircraft type data with both IATA and ICAO codes.
    # This complements the CFAPPS ICAO source which only has ICAO codes.
    #
    # @see https://openflights.org/data
    class OpenFlights < Processors::Base
      DEFAULT_URL = 'https://raw.githubusercontent.com/jpatokal/openflights/master/data/planes.dat'

      # CSV column indices (0-based) - OpenFlights uses headerless CSV
      COLUMNS = {
        name: 0,
        iata_code: 1,
        icao_code: 2
      }.freeze

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          csv = CSV.parse(csv_data, headers: false, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::AircraftType::OpenFlightsAircraftTypeSource.transaction do
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
          name = row[COLUMNS[:name]]&.strip
          iata_code = clean_code(row[COLUMNS[:iata_code]])
          icao_code = clean_code(row[COLUMNS[:icao_code]])

          return { skipped: true, reason: 'No name' } if name.blank?

          # Skip if no usable code
          return { skipped: true, reason: 'No IATA or ICAO code' } if iata_code.blank? && icao_code.blank?

          # Use ICAO code as type_code if available, otherwise IATA
          type_code = icao_code.presence || iata_code

          record = Source::AircraftType::OpenFlightsAircraftTypeSource.find_or_initialize_by(
            type_code: type_code
          )

          record.assign_attributes(
            name: name,
            type_code: type_code,
            iata_code: iata_code,
            import_date: import_timestamp,
            data: {
              'openflights_icao' => icao_code,
              'openflights_iata' => iata_code
            }.compact
          )

          if record.save
            { aircraft_type: record }
          else
            { error: { name: name, type_code: type_code, errors: record.errors.full_messages } }
          end
        end

        def clean_code(value)
          return nil if value.blank? || value == '\\N'

          cleaned = value.strip
          cleaned.present? ? cleaned : nil
        end
      end
    end
  end
end
