# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'uri'

module Processors
  module AircraftType
    module VRS
      # Processor for importing aircraft type data from VRS (Virtual Radar Server) standing data.
      #
      # The VRS model-type data is organised by the first letter of the ICAO type code:
      # - A.csv through Z.csv (plus -.csv for non-standard codes)
      #
      # @example Import all aircraft types from GitHub
      #   Processors::AircraftType::VRS::ModelType.import_all_from_github
      #
      # @example Import a specific letter from GitHub
      #   Processors::AircraftType::VRS::ModelType.import_letter('B')
      #
      # @see https://github.com/vradarserver/standing-data/tree/main/model-type/schema-01
      class ModelType < Processors::Base
        # Base URL for fetching CSV files from GitHub
        GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/model-type/schema-01'

        # Batch size for database operations
        BATCH_SIZE = 500

        # CSV column mappings to source table fields
        # VRS columns: ICAO, Manufacturer, Model, Engines, EngineTypeCode,
        #              EnginePlacementCode, SpeciesCode, WakeTurbulenceCode, IsActive
        COLUMN_MAPPINGS = {
          'ICAO' => :type_code,
          'Manufacturer' => :manufacturer,
          'Model' => :name,
          'Engines' => :engines,
          'EngineTypeCode' => :engine_type,
          'WakeTurbulenceCode' => :wtc
        }.freeze

        # Columns to store in the JSONB data field
        DATA_COLUMNS = %w[EnginePlacementCode SpeciesCode IsActive].freeze

        # Maps VRS species codes to our category values
        SPECIES_TO_CATEGORY = {
          'L' => 'airplane',     # Landplane
          'S' => 'seaplane',     # Seaplane
          'A' => 'seaplane',     # Amphibian
          'H' => 'helicopter',   # Helicopter
          'G' => 'helicopter',   # Gyrocopter
          'T' => 'airplane'      # Tilt-wing
        }.freeze

        # All available letter files (A-Z plus -)
        LETTERS = (['-'] + ('A'..'Z').to_a).freeze

        class << self
          # Imports all aircraft type data from GitHub.
          #
          # @param progress [Boolean] Whether to show progress bar
          # @return [Hash] Import results with :success_count, :error_count, :errors
          def import_all_from_github(progress: true)
            total_success = 0
            total_errors = 0
            all_errors = []

            progress_bar = progress ? create_progress_bar(LETTERS.count) : nil

            with_bulk_import do
              LETTERS.each do |letter|
                result = import_letter(letter)
                total_success += result[:success_count]
                total_errors += result[:error_count]
                all_errors.concat(result[:errors])

                progress_bar&.increment!
              end
            end

            new_import_report(all_errors, total_success + total_errors)

            { success_count: total_success, error_count: total_errors, errors: all_errors }
          end

          # Imports aircraft type data for a specific letter from GitHub.
          #
          # @param letter [String] The letter (A-Z or -)
          # @return [Hash] Import results
          def import_letter(letter)
            letter = letter.upcase unless letter == '-'
            unless LETTERS.include?(letter)
              raise ArgumentError, "Invalid letter: #{letter}. Must be A-Z or -."
            end

            url = "#{GITHUB_RAW_BASE}/#{letter}.csv"
            csv_data = fetch_url(url)

            if csv_data.nil?
              Rails.logger.info "No data found for letter #{letter}"
              return { success_count: 0, error_count: 0, errors: [] }
            end

            import_csv_data(csv_data, source_name: "GitHub:#{letter}")
          end

          # Imports from a local directory.
          #
          # @param directory_path [String] Path to schema-01 directory
          # @return [Hash] Import results
          def import(directory_path)
            unless File.directory?(directory_path)
              raise ArgumentError, "Directory not found: #{directory_path}"
            end

            csv_files = Dir.glob(File.join(directory_path, '*.csv')).sort
            if csv_files.empty?
              raise ArgumentError, "No CSV files found in #{directory_path}"
            end

            total_success = 0
            total_errors = 0
            all_errors = []

            progress_bar = create_progress_bar(csv_files.count)

            with_bulk_import do
              csv_files.each do |file_path|
                csv_data = File.read(file_path, encoding: 'utf-8')
                result = import_csv_data(csv_data, source_name: File.basename(file_path))

                total_success += result[:success_count]
                total_errors += result[:error_count]
                all_errors.concat(result[:errors])

                progress_bar.increment!
              end
            end

            new_import_report(all_errors, total_success + total_errors)

            { success_count: total_success, error_count: total_errors, errors: all_errors }
          end

          private

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

            # Handle UTF-8 BOM if present
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
            type_code = row['ICAO']&.strip
            name = row['Model']&.strip

            # Skip rows without required fields
            if type_code.blank?
              return { error: { name: name, errors: ['Missing ICAO type code'] } }
            end

            if name.blank?
              return { error: { type_code: type_code, errors: ['Missing model name'] } }
            end

            attributes = build_attributes(row, type_code, name, batch_timestamp)

            { attributes: attributes }
          end

          # Builds attribute hash from CSV row.
          # All records have the same keys to ensure upsert_all compatibility.
          #
          # @param row [CSV::Row] The CSV row
          # @param type_code [String] Normalised type code
          # @param name [String] Model name
          # @param batch_timestamp [Time] Import timestamp
          # @return [Hash] Attributes for source record
          def build_attributes(row, type_code, name, batch_timestamp)
            manufacturer = row['Manufacturer']&.strip
            engines_raw = row['Engines']&.strip
            engine_type = row['EngineTypeCode']&.strip
            wtc = row['WakeTurbulenceCode']&.strip
            species_code = row['SpeciesCode']&.strip

            # Parse engines - handle 'C' for combined configurations
            engines = if engines_raw.present? && engines_raw.match?(/\A\d+\z/)
                        engines_raw.to_i
                      end

            # Convert species code to category
            category = SPECIES_TO_CATEGORY[species_code]

            # Build data JSONB
            data = {}
            DATA_COLUMNS.each do |col|
              value = row[col]&.strip
              data[col.underscore] = value if value.present?
            end

            {
              type_code: type_code,
              name: name,
              manufacturer: manufacturer,
              engines: engines,
              engine_type: engine_type,
              wtc: wtc,
              category: category,
              import_date: batch_timestamp,
              data: data
            }
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
              r[:type] = 'Source::AircraftType::VRSAircraftTypeSource'
            end

            # Use insert_all since there's no unique constraint - duplicates will just be inserted
            # For a proper upsert we'd need a unique index on (type_code, name, type)
            Source::AircraftType::VRSAircraftTypeSource.insert_all(
              records,
              record_timestamps: false
            )
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