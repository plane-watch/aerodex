# frozen_string_literal: true

require 'csv'

module Processors
  module Airport
    # Processor for importing airport data from OpenFlights.org
    #
    # OpenFlights provides airport data in a headerless CSV format with 14 columns.
    # Data is from January 2017 vintage.
    #
    # @see https://openflights.org/data
    class OpenFlights < Processors::Base
      DEFAULT_URL = 'https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat'

      # CSV column indices (0-based) - OpenFlights uses headerless CSV
      COLUMNS = {
        id: 0,
        name: 1,
        city: 2,
        country: 3,
        iata_code: 4,
        icao_code: 5,
        latitude: 6,
        longitude: 7,
        elevation: 8,
        timezone_offset: 9,
        dst: 10,
        timezone: 11,
        airport_type: 12,
        source: 13
      }.freeze

      class << self
        def import(url = DEFAULT_URL)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          # Preload countries for name-to-ISO lookup
          @countries_by_name = build_country_name_lookup

          # OpenFlights uses headerless CSV
          csv = CSV.parse(csv_data, headers: false, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Airport::OpenFlightsAirportSource.transaction do
            csv.each do |row|
              result = import_row(row, batch_import_timestamp)
              import_errors << result[:error] if result[:error]
              records_processed += 1
              progress_bar.increment!
            end
          end

          new_import_report(import_errors, records_processed)

          import_errors.empty? ? true : import_errors
        ensure
          @countries_by_name = nil
        end

        private

        def import_row(row, import_timestamp)
          # Extract and clean values
          icao_code = clean_code(row[COLUMNS[:icao_code]])
          iata_code = clean_code(row[COLUMNS[:iata_code]])
          name = row[COLUMNS[:name]]&.strip

          # Skip if no name
          return { skipped: true, reason: 'No name' } if name.blank?

          # Skip if no usable identifier
          if icao_code.blank? && iata_code.blank?
            return { skipped: true, reason: 'No ICAO or IATA code' }
          end

          # Find existing record or create new one
          record = find_or_initialize_record(icao_code, iata_code, name)

          record.assign_attributes(
            name: name,
            icao_code: icao_code,
            iata_code: iata_code,
            city: row[COLUMNS[:city]]&.strip,
            country_code: lookup_country_code(row[COLUMNS[:country]]&.strip),
            latitude: parse_decimal(row[COLUMNS[:latitude]]),
            longitude: parse_decimal(row[COLUMNS[:longitude]]),
            elevation: parse_decimal(row[COLUMNS[:elevation]]),
            timezone: row[COLUMNS[:timezone]]&.strip,
            airport_type: row[COLUMNS[:airport_type]]&.strip,
            import_date: import_timestamp,
            data: {
              openflights_id: row[COLUMNS[:id]],
              country_name: row[COLUMNS[:country]]&.strip,
              timezone_offset: row[COLUMNS[:timezone_offset]],
              dst: row[COLUMNS[:dst]]
            }
          )

          if record.save
            { airport: record }
          else
            { error: { name: name, icao: icao_code, iata: iata_code, errors: record.errors.full_messages } }
          end
        end

        def find_or_initialize_record(icao_code, iata_code, name)
          # Prefer to match by ICAO code first
          if icao_code.present?
            Source::Airport::OpenFlightsAirportSource.find_or_initialize_by(icao_code: icao_code)
          else
            # Fall back to IATA + name for disambiguation
            Source::Airport::OpenFlightsAirportSource.find_or_initialize_by(
              iata_code: iata_code,
              name: name
            )
          end
        end

        # Cleans airport codes - OpenFlights uses \N for null values
        def clean_code(value)
          return nil if value.blank? || value == '\\N'

          cleaned = value.strip
          cleaned.present? ? cleaned : nil
        end

        def parse_decimal(value)
          return nil if value.blank? || value == '\\N'

          BigDecimal(value.to_s)
        rescue ArgumentError
          nil
        end

        # Builds a lookup hash mapping country names to ISO 2-char codes.
        # Includes common name variations used by OpenFlights.
        #
        # @return [Hash<String, String>] Country name => ISO code
        def build_country_name_lookup
          lookup = {}

          ::Country.find_each do |country|
            lookup[country.name.downcase] = country.iso_2char_code
          end

          # Add OpenFlights-specific variations that differ from ISO names
          openflights_aliases.each do |alias_name, iso_code|
            lookup[alias_name.downcase] = iso_code
          end

          lookup
        end

        # Looks up the ISO country code from an OpenFlights country name.
        #
        # @param country_name [String, nil] The country name from OpenFlights
        # @return [String, nil] The ISO 2-char code or nil if not found
        def lookup_country_code(country_name)
          return nil if country_name.blank?

          @countries_by_name[country_name.downcase]
        end

        # OpenFlights uses some country names that differ from ISO standard names.
        # This hash maps OpenFlights names to ISO 2-char codes.
        #
        # @return [Hash<String, String>]
        # rubocop:disable Metrics/MethodLength
        def openflights_aliases
          {
            'Burma' => 'MM',
            'Congo (Brazzaville)' => 'CG',
            'Congo (Kinshasa)' => 'CD',
            'Cote d\'Ivoire' => 'CI',
            'Czech Republic' => 'CZ',
            'East Timor' => 'TL',
            'Falkland Islands' => 'FK',
            'Hong Kong' => 'HK',
            'Iran' => 'IR',
            'Johnston Atoll' => 'UM',
            'Laos' => 'LA',
            'Macau' => 'MO',
            'Macedonia' => 'MK',
            'Micronesia' => 'FM',
            'Moldova' => 'MD',
            'Netherlands Antilles' => 'AN',
            'North Korea' => 'KP',
            'Palestine' => 'PS',
            'Palestinian Territory' => 'PS',
            'Reunion' => 'RE',
            'Russia' => 'RU',
            'Saint Helena' => 'SH',
            'South Korea' => 'KR',
            'Svalbard' => 'SJ',
            'Syria' => 'SY',
            'Taiwan' => 'TW',
            'Tanzania' => 'TZ',
            'United States' => 'US',
            'Venezuela' => 'VE',
            'Vietnam' => 'VN',
            'Virgin Islands' => 'VI',
            'British Virgin Islands' => 'VG',
            'West Bank' => 'PS'
          }
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
