# frozen_string_literal: true

require 'csv'

module Processors
  module Country
    # Processor for importing country data from OurAirports.com
    #
    # OurAirports provides country data with ISO codes and continent information.
    #
    # @see https://ourairports.com/data/
    class OurAirports < Processors::Base
      DEFAULT_URL = 'https://davidmegginson.github.io/ourairports-data/countries.csv'

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Country::OurAirportsCountrySource.transaction do
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
          name = row['name']&.strip
          iso_code = row['code']&.strip

          return { skipped: true, reason: 'No name' } if name.blank?
          return { skipped: true, reason: 'No ISO code' } if iso_code.blank?

          record = Source::Country::OurAirportsCountrySource.find_or_initialize_by(
            iso_2char_code: iso_code
          )

          record.assign_attributes(
            name: name,
            iso_2char_code: iso_code,
            import_date: import_timestamp,
            data: {
              'ourairports_id' => row['id'],
              'continent' => row['continent']&.strip,
              'wikipedia_link' => row['wikipedia_link']&.strip,
              'keywords' => row['keywords']&.strip
            }.compact
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
