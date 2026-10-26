# frozen_string_literal: true

require 'nokogiri'

module Processors
  module Operator
    # Processor for importing operator data from airlinecodes.info.
    #
    # This source provides country and callsign information for airlines,
    # which is useful for enriching operators that lack country data.
    #
    # Data attribution: https://airlinecodes.info
    #
    # @example Import specific ICAO codes
    #   Processors::Operator::AirlineCodes.import(icao_codes: %w[QFA UAL BAW])
    #
    # @example Import all ICAO codes from existing VRS sources
    #   icao_codes = Source::Operator::VRSDataOperatorSource.pluck(:icao_code).compact.uniq
    #   Processors::Operator::AirlineCodes.import(icao_codes: icao_codes)
    #
    # @example Import codes that are causing combine errors
    #   Processors::Operator::AirlineCodes.import_missing_countries
    class AirlineCodes < Processors::Base
      # Base URL for airlinecodes.info
      BASE_URL = 'https://airlinecodes.info'

      # Delay between requests in seconds (be polite to the server)
      REQUEST_DELAY = 0.2

      # User agent string identifying our scraper
      USER_AGENT = 'Aerodex/1.0 (Aviation Database; +https://github.com/plane-watch/aerodex)'

      class << self
        # Imports operator data for the specified ICAO codes.
        #
        # @param icao_codes [Array<String>] List of ICAO codes to scrape
        # @param skip_existing [Boolean] Skip codes that already have a source record (default: true)
        # @return [Hash] Import statistics
        def import(icao_codes:, skip_existing: true)
          raise ArgumentError, 'icao_codes is required' if icao_codes.blank?

          icao_codes = icao_codes.compact.uniq.map(&:upcase)

          if skip_existing
            existing = Source::Operator::AirlineCodesOperatorSource.where(icao_code: icao_codes).pluck(:icao_code)
            icao_codes -= existing
            Rails.logger.info "Skipping #{existing.count} existing records" if existing.any?
          end

          return { processed: 0, created: 0, errors: 0, skipped: 0 } if icao_codes.empty?

          import_icao_codes(icao_codes)
        end

        # Imports operator data for ICAO codes that are missing country information.
        # This is useful for unblocking the operator combine process.
        #
        # @return [Hash] Import statistics
        def import_missing_countries
          # Find operators without country that have ICAO codes
          problem_icao_codes = ::Operator
                               .where(country_id: nil)
                               .where.not(icao_code: [nil, ''])
                               .pluck(:icao_code)
                               .compact
                               .uniq

          Rails.logger.info "Found #{problem_icao_codes.count} operators without country"

          import(icao_codes: problem_icao_codes)
        end

        # Imports a single ICAO code and returns the result.
        # Useful for testing or manual imports.
        #
        # @param icao_code [String] The ICAO code to import
        # @return [Hash] Result with :source or :error key
        def import_one(icao_code)
          icao_code = icao_code.to_s.strip.upcase
          raise ArgumentError, 'ICAO code is required' if icao_code.blank?

          data = scrape_airline_page(icao_code)

          return { error: data[:error], icao_code: icao_code } if data[:error]

          source = create_or_update_source(icao_code, data)
          { source: source, data: data }
        end

        private

        # Imports a list of ICAO codes with rate limiting and progress tracking.
        #
        # @param icao_codes [Array<String>] List of ICAO codes to import
        # @return [Hash] Import statistics
        def import_icao_codes(icao_codes)
          stats = { processed: 0, created: 0, updated: 0, errors: 0, error_details: [] }
          batch_import_timestamp = Time.current

          progress_bar = create_progress_bar(icao_codes.count)

          icao_codes.each_with_index do |icao_code, index|
            # Rate limiting - be polite to the server
            sleep(REQUEST_DELAY) if index.positive?

            begin
              data = scrape_airline_page(icao_code)

              if data[:error]
                stats[:errors] += 1
                stats[:error_details] << { icao_code: icao_code, error: data[:error] }
              else
                source = create_or_update_source(icao_code, data, batch_import_timestamp)
                if source.previously_new_record?
                  stats[:created] += 1
                else
                  stats[:updated] += 1
                end
              end
            rescue StandardError => e
              stats[:errors] += 1
              stats[:error_details] << { icao_code: icao_code, error: e.message }
              Rails.logger.error "Error scraping #{icao_code}: #{e.message}"
            end

            stats[:processed] += 1
            progress_bar.increment!
          end

          # Create import report
          new_import_report(stats[:error_details], stats[:processed])

          Rails.logger.info "AirlineCodes import complete: #{stats[:created]} created, " \
                            "#{stats[:updated]} updated, #{stats[:errors]} errors"

          stats
        end

        # Scrapes the airlinecodes.info page for a given ICAO code.
        #
        # @param icao_code [String] The ICAO code
        # @return [Hash] Parsed data or error
        def scrape_airline_page(icao_code)
          url = "#{BASE_URL}/#{icao_code}"

          response = Excon.get(url, headers: { 'User-Agent' => USER_AGENT })

          case response.status
          when 200
            parse_airline_page(response.body, icao_code)
          when 404
            { error: 'Not found' }
          else
            { error: "HTTP #{response.status}" }
          end
        rescue Excon::Error => e
          { error: e.message }
        end

        # Parses the HTML content of an airline page.
        #
        # @param html [String] The HTML content
        # @param icao_code [String] The ICAO code (for logging)
        # @return [Hash] Parsed data
        def parse_airline_page(html, icao_code)
          doc = Nokogiri::HTML(html)

          # Try to extract from meta description first (most reliable)
          # Format: "Air Express: ICAO AEJ, Callsign KHAKI EXPRESS, Country Tanzania ✈ Click here to see more."
          meta_desc = doc.at('meta[name="description"]')&.attr('content')

          data = { source_url: "#{BASE_URL}/#{icao_code}" }

          data.merge!(parse_meta_description(meta_desc)) if meta_desc

          # Fall back to / supplement with table data
          table_data = parse_data_table(doc)
          data[:callsign] ||= table_data[:callsign]
          data[:country] ||= table_data[:country]
          data[:wikipedia_url] ||= table_data[:wikipedia_url]

          # Get name from h2 if not in meta
          data[:name] ||= doc.at('h2[itemprop="name"]')&.text&.strip

          # Get IATA code if present
          iata_match = doc.text.match(/IATA:\s*(\w{2})/)
          data[:iata_code] = iata_match[1] if iata_match

          data
        end

        # Parses the meta description tag content.
        #
        # @param content [String] The meta description content
        # @return [Hash] Parsed data
        def parse_meta_description(content)
          data = {}

          # Extract name (before the colon)
          name_match = content.match(/\A([^:]+):/)
          data[:name] = name_match[1].strip if name_match

          # Extract callsign
          callsign_match = content.match(/Callsign\s+([^,]+)/i)
          data[:callsign] = callsign_match[1].strip if callsign_match

          # Extract country
          country_match = content.match(/Country\s+([^✈,]+)/i)
          data[:country] = country_match[1].strip if country_match

          data
        end

        # Parses the data table on the airline page.
        #
        # @param doc [Nokogiri::HTML::Document] The parsed HTML document
        # @return [Hash] Parsed data
        def parse_data_table(doc)
          data = {}

          doc.css('table.datagrid tr').each do |row|
            label = row.at('td.datalabel')&.text&.strip&.downcase
            value = row.at('td:last-child')&.text&.strip

            case label
            when /callsign/
              data[:callsign] = value
            when /country/
              data[:country] = value
            when /wikipedia/
              data[:wikipedia_url] = row.at('td:last-child a')&.attr('href')
            end
          end

          data
        end

        # Creates or updates a source record with the scraped data.
        #
        # @param icao_code [String] The ICAO code
        # @param data [Hash] The scraped data
        # @param import_timestamp [Time] The batch import timestamp
        # @return [Source::Operator::AirlineCodesOperatorSource] The source record
        def create_or_update_source(icao_code, data, import_timestamp = Time.current)
          source = Source::Operator::AirlineCodesOperatorSource
                   .find_or_initialize_by(icao_code: icao_code)

          source.assign_attributes(
            name: data[:name],
            iata_code: data[:iata_code],
            import_date: import_timestamp,
            data: {
              name: data[:name],
              icao_code: icao_code,
              iata_code: data[:iata_code],
              callsign: data[:callsign],
              country: data[:country],
              wikipedia_url: data[:wikipedia_url],
              source_url: data[:source_url],
              attribution: Source::Operator::AirlineCodesOperatorSource.attribution
            }
          )

          source.save!
          source
        end
      end
    end
  end
end
