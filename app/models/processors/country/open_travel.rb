# frozen_string_literal: true

require 'csv'

module Processors
  module Country
    # Processor for importing country data from OpenTravel's optd_countries feed.
    #
    # The feed is caret-separated and supplies the ISO 2 character, ISO 3
    # character and numeric codes alongside the country name and capital.
    #
    # @see https://github.com/opentraveldata/opentraveldata
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

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false if csv_data.nil?

          # liberal parsing is needed for nested quotes inside fields
          csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8', col_sep: '^')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Country::OpenTravelCountrySource.transaction do
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
          attributes = row.headers.each_with_object({}) do |key, memo|
            transformed_data = transform_field(key, row[key])
            next if transformed_data.nil?

            memo[transformed_data[:key]] = transformed_data[:value]
          end

          name = attributes['name']
          iso_2char_code = attributes['iso_2char_code']
          iso_3char_code = attributes['iso_3char_code']

          return { skipped: true, reason: 'No name' } if name.blank?
          return { skipped: true, reason: 'No ISO 2 character code' } if iso_2char_code.blank?
          return { skipped: true, reason: 'No ISO 3 character code' } if iso_3char_code.blank?

          record = Source::Country::OpenTravelCountrySource.find_or_initialize_by(
            iso_2char_code: iso_2char_code
          )

          record.assign_attributes(
            iso_2char_code: iso_2char_code,
            iso_3char_code: iso_3char_code,
            iso_num_code: attributes['iso_num_code'],
            name: name,
            capital: attributes['capital'],
            import_date: import_timestamp
          )

          if record.save
            { country: record }
          else
            { error: { name: name, iso: iso_2char_code, errors: record.errors.full_messages } }
          end
        end
      end
    end
  end
end
