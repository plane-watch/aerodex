# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'uri'
require 'tempfile'

module Processors
  module Aircraft
    # Processor for importing aircraft data from OpenSky Network's aircraft database.
    #
    # OpenSky provides a comprehensive aircraft database with metadata including
    # owner information, which is often missing from other sources like VRS.
    #
    # @example Import from OpenSky (downloads ~94MB CSV)
    #   Processors::Aircraft::Opensky.import_from_url
    #
    # @example Import from a local file
    #   Processors::Aircraft::Opensky.import('/path/to/aircraftDatabase.csv')
    #
    # @see https://opensky-network.org/datasets/metadata/
    class Opensky < Processors::Base
      # URL for the OpenSky aircraft database CSV
      OPENSKY_URL = 'https://s3.opensky-network.org/data-samples/metadata/aircraftDatabase.csv'

      # Batch size for database operations
      BATCH_SIZE = 1000

      # CSV column mappings to source table fields
      # OpenSky columns: icao24, registration, manufacturericao, manufacturername, model,
      #                  typecode, serialnumber, linenumber, icaoaircrafttype, operator,
      #                  operatorcallsign, operatoricao, operatoriata, owner, testreg,
      #                  registered, reguntil, status, built, firstflightdate,
      #                  seatconfiguration, engines, modes, adsb, acars, notes, categoryDescription
      #
      # Note: 'engines' is handled separately via parse_engine_data as it contains
      # both count and model in a single field (e.g., "x 4 x ROLLS-ROYCE RB211<br>")
      COLUMN_MAPPINGS = {
        'icao24' => :icao,
        'registration' => :registration,
        'typecode' => :type_code,
        'manufacturericao' => :manufacturer_code,
        'model' => :model,
        'serialnumber' => :serial_number,
        'owner' => :owner,
        'operator' => :operator_name,
        'operatoricao' => :operator_icao,
        'built' => :manufacture_year,
        'status' => :status,
        'registered' => :registration_date
      }.freeze

      # Regex to parse engine data in format "x {count} x {model}<br>" or similar
      # Examples:
      #   "x 4 x ROLLS-ROYCE RB211 Trent 556-61<br>" => count: 4, model: "ROLLS-ROYCE RB211 Trent 556-61"
      #   "x 2 x CFM56-5B<br>" => count: 2, model: "CFM56-5B"
      #   "1 x PRATT & WHITNEY<br>" => count: 1, model: "PRATT & WHITNEY"
      ENGINE_PATTERN = %r{
        (?:x\s*)?        # Optional leading "x "
        (\d+)            # Engine count (captured)
        \s*x\s*          # " x " separator
        (.+?)            # Engine model (captured, non-greedy)
        (?:<br>|<br/>)? # Optional HTML break tag
        \s*$             # End of string, possibly with trailing whitespace
      }ix

      # Columns to store in the JSONB data field
      DATA_COLUMNS = %w[
        manufacturername linenumber icaoaircrafttype operatorcallsign
        operatoriata testreg reguntil firstflightdate
        seatconfiguration categoryDescription
      ].freeze

      class << self
        # Downloads and imports the OpenSky aircraft database from the URL.
        #
        # @param progress [Boolean] Whether to show progress
        # @return [Hash] Import results with :success_count, :error_count, :errors
        def import_from_url(progress: true)
          Rails.logger.info 'Downloading OpenSky aircraft database...'

          # Download to temp file (94MB is too large to hold in memory)
          tempfile = download_to_tempfile(OPENSKY_URL)
          return { success_count: 0, error_count: 1, errors: [{ error: 'Failed to download' }] } unless tempfile

          begin
            import(tempfile.path, progress: progress)
          ensure
            tempfile.close
            tempfile.unlink
          end
        end

        # Imports aircraft data from a local CSV file.
        #
        # @param file_path [String] Path to the CSV file
        # @param progress [Boolean] Whether to show progress bar
        # @return [Hash] Import results
        def import(file_path, progress: true)
          raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

          # Count lines for progress bar (subtract 1 for header)
          total_lines = `wc -l < "#{file_path}"`.to_i - 1
          Rails.logger.info "Importing #{total_lines} records from OpenSky..."

          success_count = 0
          error_count = 0
          errors = []
          pending_records = []
          batch_timestamp = Time.current

          progress_bar = progress ? create_progress_bar(total_lines) : nil

          with_bulk_import do
            File.open(file_path, 'r:bom|utf-8') do |file|
              csv = CSV.new(file, headers: true)

              csv.each do |row|
                result = process_row(row, batch_timestamp)

                if result[:error]
                  error_count += 1
                  errors << result[:error] if errors.count < 100 # Limit stored errors
                elsif result[:attributes]
                  pending_records << result[:attributes]
                  success_count += 1
                end

                # Flush in batches
                if pending_records.size >= BATCH_SIZE
                  flush_records(pending_records)
                  pending_records.clear
                end

                progress_bar&.increment!
              end
            end

            # Flush remaining records
            flush_records(pending_records) if pending_records.any?
          end

          new_import_report(errors, success_count + error_count)

          { success_count: success_count, error_count: error_count, errors: errors }
        end

        private

        # Downloads a URL to a temporary file.
        #
        # @param url [String] URL to download
        # @return [Tempfile, nil] The tempfile or nil if download failed
        def download_to_tempfile(url)
          uri = URI.parse(url)
          tempfile = Tempfile.new(['opensky_aircraft', '.csv'])
          tempfile.binmode

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)

            http.request(request) do |response|
              unless response.is_a?(Net::HTTPSuccess)
                Rails.logger.error "Failed to download OpenSky data: #{response.code}"
                tempfile.close
                tempfile.unlink
                return nil
              end

              total_size = response['content-length'].to_i
              downloaded = 0

              response.read_body do |chunk|
                tempfile.write(chunk)
                downloaded += chunk.size

                # Log progress every 10MB
                if downloaded % (10 * 1024 * 1024) < chunk.size
                  percent = (downloaded.to_f / total_size * 100).round(1)
                  Rails.logger.info "Downloaded #{percent}% (#{downloaded / 1024 / 1024}MB)"
                end
              end
            end
          end

          tempfile.rewind
          Rails.logger.info "Download complete: #{tempfile.size / 1024 / 1024}MB"
          tempfile
        rescue StandardError => e
          Rails.logger.error "Error downloading OpenSky data: #{e.message}"
          tempfile&.close
          tempfile&.unlink
          nil
        end

        # Processes a single CSV row into source record attributes.
        #
        # @param row [CSV::Row] The CSV row
        # @param batch_timestamp [Time] Import timestamp for this batch
        # @return [Hash] Result with :attributes or :error, or empty hash to skip
        def process_row(row, batch_timestamp)
          icao = row['icao24']&.strip&.upcase
          registration = row['registration']&.strip

          # Skip rows without required fields
          return {} if icao.blank?
          return {} if registration.blank?

          # Skip empty/placeholder registrations
          return {} if %w[NONE UNKNOWN].include?(registration)

          # Skip military/test registrations that are just numbers
          return {} if registration.match?(/\A\d+-\d+\z/)

          attributes = build_attributes(row, icao, registration, batch_timestamp)

          { attributes: attributes }
        end

        # Builds attribute hash from CSV row.
        #
        # @param row [CSV::Row] The CSV row
        # @param icao [String] Normalised ICAO code
        # @param registration [String] Aircraft registration
        # @param batch_timestamp [Time] Import timestamp
        # @return [Hash] Attributes for source record
        def build_attributes(row, icao, registration, batch_timestamp)
          attributes = {
            icao: icao,
            registration: registration,
            import_date: batch_timestamp,
            type_code: nil,
            manufacturer_code: nil,
            model: nil,
            serial_number: nil,
            owner: nil,
            operator_name: nil,
            operator_icao: nil,
            manufacture_year: nil,
            registration_date: nil,
            engine_count: nil,
            engine_model: nil,
            status: nil,
            data: {}
          }

          # Map standard columns
          COLUMN_MAPPINGS.each do |csv_col, db_field|
            next if %w[icao24 registration].include?(csv_col)

            value = row[csv_col]&.strip
            next if value.blank?

            # Skip "Private" as owner - not useful
            next if db_field == :owner && value == 'Private'

            # Type conversions
            case db_field
            when :manufacture_year
              # Format is "YYYY-01-01" - extract year
              if value.match?(/\A\d{4}/)
                value = value[0, 4].to_i
                value = nil if value.zero?
              else
                value = nil
              end
            when :registration_date
              # Format is "YYYY-MM-DD" - parse as date
              begin
                value = Date.parse(value) if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
              rescue Date::Error
                value = nil
              end
            when :icao
              value = value.upcase
            end

            attributes[db_field] = value
          end

          # Parse engine data (contains both count and model in a single field)
          engine_data = parse_engine_data(row['engines'])
          attributes[:engine_count] = engine_data[:count]
          attributes[:engine_model] = engine_data[:model]

          # Store extra data in JSONB field
          DATA_COLUMNS.each do |col|
            value = row[col]&.strip
            attributes[:data][col.underscore] = value if value.present?
          end

          attributes
        end

        # Parses engine data from the OpenSky 'engines' field.
        #
        # The field contains engine count and model in formats like:
        #   "x 4 x ROLLS-ROYCE RB211 Trent 556-61<br>"
        #   "x 2 x CFM56-5B<br>"
        #   "1 x PRATT & WHITNEY PW4000<br>"
        #   "2 x PRATT &amp; WHITNEY CANADA PT6A-21&nbsp;&nbsp;..."
        #
        # @param raw_value [String, nil] The raw engines field value
        # @return [Hash] Hash with :count (Integer or nil) and :model (String or nil)
        def parse_engine_data(raw_value)
          result = { count: nil, model: nil }
          return result if raw_value.blank?

          # Decode HTML entities using Nokogiri (handles &amp;, &nbsp;, etc.)
          # CGI.unescapeHTML only handles basic XML entities, not HTML named entities
          cleaned = Nokogiri::HTML.fragment(raw_value).text

          # Remove trailing ellipsis
          cleaned = cleaned.gsub(/\.{2,}\s*$/, '').strip

          # Normalise multiple spaces to single space
          cleaned = cleaned.gsub(/\s+/, ' ')

          return result if cleaned.blank?

          # Try to match the expected pattern
          if (match = cleaned.match(ENGINE_PATTERN))
            result[:count] = match[1].to_i
            result[:model] = match[2].strip
          else
            # Fallback: store the cleaned value as model if we can't parse it
            # This ensures we don't lose data even if format is unexpected
            result[:model] = cleaned
          end

          result
        end

        # Flushes pending records to the database using upsert.
        #
        # @param records [Array<Hash>] Array of attribute hashes
        def flush_records(records)
          return if records.empty?

          # Add timestamps and type
          now = Time.current
          records.each do |r|
            r[:created_at] = now
            r[:updated_at] = now
            r[:type] = 'Source::Aircraft::OpenskyAircraftSource'
          end

          Source::Aircraft::OpenskyAircraftSource.upsert_all(
            records,
            unique_by: %i[icao type],
            update_only: %i[
              registration serial_number model type_code manufacturer_code
              owner operator_name operator_icao manufacture_year status
              registration_date engine_count engine_model data import_date
            ]
          )
        end
      end
    end
  end
end
