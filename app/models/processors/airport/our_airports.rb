# frozen_string_literal: true

require 'csv'

module Processors
  module Airport
    # Processor for importing airport data from OurAirports.com
    #
    # OurAirports provides comprehensive, daily-updated airport data with headers.
    # This is the most current and complete open source airport dataset.
    #
    # @see https://ourairports.com/data/
    class OurAirports < Processors::Base
      DEFAULT_URL = 'https://davidmegginson.github.io/ourairports-data/airports.csv'

      # Field mapping from CSV headers to our schema
      FIELD_MAP = {
        'ident' => :ident,
        'type' => :airport_type,
        'name' => :name,
        'latitude_deg' => :latitude,
        'longitude_deg' => :longitude,
        'elevation_ft' => :elevation,
        'iso_country' => :country_code,
        'iso_region' => nil, # Stored in data
        'municipality' => :municipality,
        'scheduled_service' => nil, # Stored in data
        'gps_code' => nil, # Often same as ICAO
        'iata_code' => :iata_code,
        'local_code' => nil, # Stored in data
        'icao_code' => :icao_code # Added in recent OurAirports data
      }.freeze

      # Airport types we want to import (skip closed airports and seaplane bases by default)
      VALID_TYPES = %w[
        large_airport
        medium_airport
        small_airport
        heliport
        balloonport
      ].freeze

      class << self
        def import(url = DEFAULT_URL, include_closed: false)
          csv_data = get_source_from_url(url)
          return false unless csv_data

          csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8')

          batch_import_timestamp = Time.current
          import_errors = []
          records_processed = 0
          records_skipped = 0

          progress_bar = create_progress_bar(csv.count)

          Source::Airport::OurAirportsAirportSource.transaction do
            csv.each do |row|
              # Skip closed airports unless explicitly included
              if !include_closed && row['type'] == 'closed'
                records_skipped += 1
                progress_bar.increment!
                next
              end

              result = import_row(row, batch_import_timestamp)
              if result[:error]
                import_errors << result[:error]
              elsif result[:skipped]
                records_skipped += 1
              end
              records_processed += 1
              progress_bar.increment!
            end
          end

          Rails.logger.info "OurAirports import: #{records_processed} processed, #{records_skipped} skipped"

          new_import_report(import_errors, records_processed)

          import_errors.empty? ? true : import_errors
        end

        private

        def import_row(row, import_timestamp)
          ident = row['ident']&.strip
          name = row['name']&.strip

          return { skipped: true, reason: 'No ident' } if ident.blank?
          return { skipped: true, reason: 'No name' } if name.blank?

          # Extract codes - OurAirports provides multiple code types
          icao_code = extract_icao_code(row)
          iata_code = clean_code(row['iata_code'])

          record = Source::Airport::OurAirportsAirportSource.find_or_initialize_by(ident: ident)

          record.assign_attributes(
            name: name,
            icao_code: icao_code,
            iata_code: iata_code,
            ident: ident,
            municipality: row['municipality']&.strip,
            country_code: row['iso_country']&.strip,
            latitude: parse_decimal(row['latitude_deg']),
            longitude: parse_decimal(row['longitude_deg']),
            elevation: parse_decimal(row['elevation_ft']),
            timezone: nil, # OurAirports doesn't provide timezone directly
            airport_type: row['type']&.strip,
            import_date: import_timestamp,
            data: build_data_hash(row)
          )

          if record.save
            { airport: record }
          else
            { error: { ident: ident, name: name, errors: record.errors.full_messages } }
          end
        end

        # Extracts ICAO code, preferring explicit icao_code field over gps_code
        def extract_icao_code(row)
          # First try the explicit ICAO code field (if present in the CSV)
          icao = clean_code(row['icao_code'])
          return icao if icao.present?

          # Fall back to GPS code if it looks like an ICAO code (4 chars, no numbers)
          gps = clean_code(row['gps_code'])
          return gps if gps.present? && gps.match?(/\A[A-Z]{4}\z/)

          nil
        end

        def clean_code(value)
          return nil if value.blank?

          cleaned = value.strip
          cleaned.present? ? cleaned : nil
        end

        def parse_decimal(value)
          return nil if value.blank?

          BigDecimal(value.to_s)
        rescue ArgumentError
          nil
        end

        # Builds the data hash with additional fields not in our schema
        def build_data_hash(row)
          {
            'ourairports_id' => row['id'],
            'iso_region' => row['iso_region']&.strip,
            'continent' => row['continent']&.strip,
            'scheduled_service' => row['scheduled_service']&.strip,
            'gps_code' => row['gps_code']&.strip,
            'local_code' => row['local_code']&.strip,
            'home_link' => row['home_link']&.strip,
            'wikipedia_link' => row['wikipedia_link']&.strip,
            'keywords' => row['keywords']&.strip
          }.compact
        end
      end
    end
  end
end
