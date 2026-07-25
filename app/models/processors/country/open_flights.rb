# frozen_string_literal: true

require 'csv'

module Processors
  module Country
    # Processor for importing country data from OpenFlights.org
    #
    # OpenFlights provides country data with ISO and DAFIF codes.
    # DAFIF codes are used in military aviation systems.
    #
    # @see https://openflights.org/data
    class OpenFlights < Processors::Base
      DEFAULT_URL = 'https://raw.githubusercontent.com/jpatokal/openflights/master/data/countries.dat'

      # CSV column indices (0-based) - OpenFlights uses headerless CSV
      COLUMNS = {
        name: 0,
        iso_code: 1,
        dafif_code: 2
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

          Source::Country::OpenFlightsCountrySource.transaction do
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
          iso_code = row[COLUMNS[:iso_code]]&.strip

          return { skipped: true, reason: 'No name' } if name.blank?
          return { skipped: true, reason: 'No ISO code' } if iso_code.blank?

          record = Source::Country::OpenFlightsCountrySource.find_or_initialize_by(
            iso_2char_code: iso_code
          )

          record.assign_attributes(
            name: name,
            iso_2char_code: iso_code,
            import_date: import_timestamp,
            data: {
              'dafif_code' => row[COLUMNS[:dafif_code]]&.strip
            }
          )

          if record.save
            { country: record }
          else
            { error: { name: name, iso: iso_code, errors: record.errors.full_messages } }
          end
        end
      end
    end
  end
end
