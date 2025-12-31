# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'uri'

module Processors
  module Aircraft
    module VRS
      # Processor for importing aircraft data from VRS (Virtual Radar Server) standing data.
      #
      # The VRS standing data repository organises aircraft by ICAO Mode-S code segments:
      # - Level 1: First hex digit (0-F)
      # - Level 2: First two hex digits (00-FF)
      # - File: First three hex digits as CSV (000.csv - FFF.csv)
      #
      # @example Import from a local clone of the repository
      #   Processors::Aircraft::VRS::StandingData.import('/path/to/standing-data/aircraft/schema-01')
      #
      # @example Import a specific ICAO range from GitHub
      #   Processors::Aircraft::VRS::StandingData.import_icao_range('7CA')
      #
      # @see https://github.com/vradarserver/standing-data/tree/main/aircraft/schema-01
      class StandingData < Processors::Aircraft::Base
        # Base URL for fetching CSV files from GitHub
        GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/aircraft/schema-01'

        # GitHub API URL for listing repository tree
        GITHUB_API_TREE = 'https://api.github.com/repos/vradarserver/standing-data/git/trees/main?recursive=1'

        # Batch size for database operations
        BATCH_SIZE = 1000

        # CSV column mappings to source table fields
        # VRS CSV columns: ICAO, Registration, ModelICAO, Manufacturer, Model,
        #                  ManufacturerAndModel, IsPrivateOperator, Operator,
        #                  AirlineCode, SerialNumber, YearBuilt
        COLUMN_MAPPINGS = {
          'ICAO' => :icao,
          'Registration' => :registration,
          'ModelICAO' => :type_code,
          'Manufacturer' => :manufacturer_code,
          'Model' => :model,
          'Operator' => :operator_name,
          'AirlineCode' => :operator_icao,
          'SerialNumber' => :serial_number,
          'YearBuilt' => :manufacture_year
        }.freeze

        # Columns to store in the JSONB data field
        DATA_COLUMNS = %w[ManufacturerAndModel IsPrivateOperator].freeze

        class << self
          # Imports all aircraft data from a local directory containing the VRS schema-01 structure.
          #
          # @param directory_path [String] Path to the schema-01 directory
          # @return [Hash] Import results with :success_count, :error_count, :errors
          def import(directory_path)
            unless File.directory?(directory_path)
              raise ArgumentError, "Directory not found: #{directory_path}"
            end

            csv_files = find_csv_files(directory_path)
            if csv_files.empty?
              raise ArgumentError, "No CSV files found in #{directory_path}"
            end

            with_bulk_import do
              import_files(csv_files)
            end
          end

          # Imports aircraft data for a specific ICAO range (3 hex digits) from GitHub.
          #
          # @param icao_prefix [String] The 3-character ICAO prefix (e.g., '7CA' for Australian VH- aircraft)
          # @return [Hash] Import results
          def import_icao_range(icao_prefix)
            icao_prefix = icao_prefix.upcase
            unless icao_prefix.match?(/\A[0-9A-F]{3}\z/)
              raise ArgumentError, "Invalid ICAO prefix: #{icao_prefix}. Must be 3 hex digits."
            end

            url = build_github_url(icao_prefix)
            csv_data = fetch_url(url)

            if csv_data.nil?
              Rails.logger.info "No data found for ICAO prefix #{icao_prefix}"
              return { success_count: 0, error_count: 0, errors: [] }
            end

            import_csv_data(csv_data, source_name: "GitHub:#{icao_prefix}")
          end

          # Imports multiple ICAO ranges in parallel.
          #
          # @param icao_prefixes [Array<String>] Array of 3-character ICAO prefixes
          # @return [Hash] Combined import results
          def import_icao_ranges(icao_prefixes)
            total_success = 0
            total_errors = 0
            all_errors = []

            icao_prefixes.each do |prefix|
              result = import_icao_range(prefix)
              total_success += result[:success_count]
              total_errors += result[:error_count]
              all_errors.concat(result[:errors])
            end

            { success_count: total_success, error_count: total_errors, errors: all_errors }
          end

          # Imports all available ICAO ranges from GitHub.
          # Uses the GitHub API to discover which CSV files actually exist.
          #
          # @param progress [Boolean] Whether to show progress bar
          # @return [Hash] Import results
          def import_all_from_github(progress: true)
            prefixes = fetch_available_prefixes
            if prefixes.empty?
              Rails.logger.error 'Failed to fetch available prefixes from GitHub'
              return { success_count: 0, error_count: 0, errors: [] }
            end

            Rails.logger.info "Found #{prefixes.count} CSV files to import from VRS"

            total_success = 0
            total_errors = 0
            all_errors = []

            progress_bar = progress ? create_progress_bar(prefixes.count) : nil

            with_bulk_import do
              prefixes.each do |prefix|
                result = import_icao_range(prefix)
                total_success += result[:success_count]
                total_errors += result[:error_count]
                all_errors.concat(result[:errors])

                progress_bar&.increment!
              end
            end

            new_import_report(all_errors, total_success + total_errors)

            { success_count: total_success, error_count: total_errors, errors: all_errors }
          end

          # Fetches the list of available ICAO prefixes from the GitHub API.
          # This queries the repository tree to find all CSV files in the aircraft/schema-01 directory.
          #
          # @return [Array<String>] Array of available 3-character ICAO prefixes
          def fetch_available_prefixes
            response = fetch_github_api(GITHUB_API_TREE)
            return [] if response.nil?

            tree = JSON.parse(response)
            csv_pattern = %r{\Aaircraft/schema-01/[0-9A-F]/[0-9A-F]{2}/([0-9A-F]{3})\.csv\z}i

            tree['tree']
              .filter_map { |item| item['path'].match(csv_pattern)&.captures&.first&.upcase }
              .sort
          rescue JSON::ParserError => e
            Rails.logger.error "Failed to parse GitHub API response: #{e.message}"
            []
          end

          private

          # Fetches content from the GitHub API with appropriate headers.
          #
          # @param url [String] GitHub API URL
          # @return [String, nil] Response body or nil if failed
          def fetch_github_api(url)
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true

            request = Net::HTTP::Get.new(uri)
            request['Accept'] = 'application/vnd.github.v3+json'
            request['User-Agent'] = 'Aerodex-Aircraft-Importer'

            response = http.request(request)

            case response
            when Net::HTTPSuccess
              response.body
            else
              Rails.logger.warn "GitHub API request failed: #{response.code} #{response.message}"
              nil
            end
          rescue StandardError => e
            Rails.logger.error "GitHub API error: #{e.message}"
            nil
          end

          # Finds all CSV files in the VRS directory structure.
          #
          # @param directory_path [String] Path to schema-01 directory
          # @return [Array<String>] Paths to CSV files
          def find_csv_files(directory_path)
            Dir.glob(File.join(directory_path, '*', '*', '*.csv')).sort
          end

          # Imports multiple CSV files with progress tracking.
          #
          # @param csv_files [Array<String>] Paths to CSV files
          # @return [Hash] Import results
          def import_files(csv_files)
            total_success = 0
            total_errors = 0
            all_errors = []

            progress_bar = create_progress_bar(csv_files.count)

            csv_files.each do |file_path|
              csv_data = File.read(file_path, encoding: 'utf-8')
              result = import_csv_data(csv_data, source_name: File.basename(file_path))

              total_success += result[:success_count]
              total_errors += result[:error_count]
              all_errors.concat(result[:errors])

              progress_bar.increment!
            end

            new_import_report(all_errors, total_success + total_errors)

            { success_count: total_success, error_count: total_errors, errors: all_errors }
          end

          # Imports CSV data into the source table.
          #
          # @param csv_data [String] Raw CSV content
          # @param source_name [String] Name for logging purposes
          # @return [Hash] Import results
          def import_csv_data(csv_data, source_name:)
            success_count = 0
            error_count = 0
            errors = []
            pending_records = []
            batch_timestamp = Time.current

            # Handle UTF-8 BOM if present (VRS files have BOM)
            csv_data = csv_data.dup.force_encoding('UTF-8')
            csv_data = csv_data.sub(/\A\xEF\xBB\xBF/u, '')

            csv = CSV.parse(csv_data, headers: true)

            csv.each do |row|
              result = process_row(row, batch_timestamp)

              if result[:error]
                error_count += 1
                errors << result[:error]
              else
                pending_records << result[:attributes]
                success_count += 1
              end

              # Flush in batches
              if pending_records.size >= BATCH_SIZE
                flush_records(pending_records)
                pending_records.clear
              end
            end

            # Flush remaining records
            flush_records(pending_records) if pending_records.any?

            { success_count: success_count, error_count: error_count, errors: errors }
          rescue CSV::MalformedCSVError => e
            Rails.logger.error "CSV parsing error in #{source_name}: #{e.message}"
            { success_count: 0, error_count: 1, errors: [{ source: source_name, error: e.message }] }
          end

          # Processes a single CSV row into source record attributes.
          #
          # @param row [CSV::Row] The CSV row
          # @param batch_timestamp [Time] Import timestamp for this batch
          # @return [Hash] Result with :attributes or :error
          def process_row(row, batch_timestamp)
            icao = row['ICAO']&.strip&.upcase
            registration = row['Registration']&.strip

            # Skip rows without required fields
            if icao.blank?
              return { error: { registration: registration, errors: ['Missing ICAO code'] } }
            end

            if registration.blank?
              return { error: { icao: icao, errors: ['Missing registration'] } }
            end

            # Skip fake codes (ground vehicles, towers, etc.)
            type_code = row['ModelICAO']&.strip
            if type_code&.start_with?('-')
              return { error: { icao: icao, errors: ["Skipping fake type code: #{type_code}"] } }
            end

            attributes = build_attributes(row, icao, registration, batch_timestamp)

            { attributes: attributes }
          end

          # Builds attribute hash from CSV row.
          # All records have the same keys to ensure upsert_all compatibility.
          #
          # @param row [CSV::Row] The CSV row
          # @param icao [String] Normalised ICAO code
          # @param registration [String] Aircraft registration
          # @param batch_timestamp [Time] Import timestamp
          # @return [Hash] Attributes for source record
          def build_attributes(row, icao, registration, batch_timestamp)
            # Initialise all fields with nil for consistent keys across records
            attributes = {
              icao: icao,
              registration: registration,
              import_date: batch_timestamp,
              type_code: nil,
              manufacturer_code: nil,
              model: nil,
              operator_name: nil,
              operator_icao: nil,
              serial_number: nil,
              manufacture_year: nil,
              data: {}
            }

            # Map standard columns
            COLUMN_MAPPINGS.each do |csv_col, db_field|
              next if %w[ICAO Registration].include?(csv_col)

              value = row[csv_col]&.strip
              next if value.blank?

              # Type conversions
              case db_field
              when :manufacture_year
                value = value.to_i if value.present? && value.match?(/\A\d+\z/)
                value = nil if value.is_a?(Integer) && value.zero?
              end

              attributes[db_field] = value
            end

            # Normalise model if present
            attributes[:model] = normalise_model(attributes[:model]) if attributes[:model].present?

            # Store extra data in JSONB field
            DATA_COLUMNS.each do |col|
              value = row[col]&.strip
              attributes[:data][col] = value if value.present?
            end

            attributes
          end

          # Flushes pending records to the database using upsert.
          #
          # @param records [Array<Hash>] Array of attribute hashes
          def flush_records(records)
            return if records.empty?

            # Add timestamps
            now = Time.current
            records.each do |r|
              r[:created_at] = now
              r[:updated_at] = now
              r[:type] = 'Source::Aircraft::VRSAircraftSource'
            end

            Source::Aircraft::VRSAircraftSource.upsert_all(
              records,
              unique_by: %i[icao type],
              update_only: %i[
                registration serial_number model type_code manufacturer_code
                operator_name operator_icao manufacture_year data import_date
              ]
            )
          end

          # Builds the GitHub raw URL for a given ICAO prefix.
          #
          # @param icao_prefix [String] 3-character hex prefix
          # @return [String] Full URL to CSV file
          def build_github_url(icao_prefix)
            first = icao_prefix[0]
            first_two = icao_prefix[0, 2]
            "#{GITHUB_RAW_BASE}/#{first}/#{first_two}/#{icao_prefix}.csv"
          end

          # Fetches content from a URL.
          #
          # @param url [String] URL to fetch
          # @return [String, nil] Response body or nil if not found
          def fetch_url(url)
            uri = URI.parse(url)
            response = Net::HTTP.get_response(uri)

            case response
            when Net::HTTPSuccess
              response.body
            when Net::HTTPNotFound
              nil
            else
              Rails.logger.warn "Failed to fetch #{url}: #{response.code} #{response.message}"
              nil
            end
          rescue StandardError => e
            Rails.logger.error "Error fetching #{url}: #{e.message}"
            nil
          end
        end
      end
    end
  end
end