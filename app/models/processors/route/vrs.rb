# frozen_string_literal: true

require 'csv'
require 'json'

module Processors
  module Route
    # The class length below is driven by the comprehensive method documentation
    # the project style guide mandates, not by excessive logic; the cop is
    # disabled here rather than stripping that documentation.
    # Imports airline route data from the VRS (Virtual Radar Server)
    # standing-data GitHub repository into the route_sources table.
    #
    # The repository organises route CSV files under routes/schema-01/<LETTER>/,
    # one file per airline named "<CODE>-all.csv" (<=10,000 routes) or split into
    # "<CODE>-<digit>.csv" files for larger airlines.
    #
    # This processor stores the rows verbatim; it does NOT resolve airlines or
    # airports. The combine step (Processors::Route::Route) resolves those against
    # the existing database.
    #
    # @example Import a single airline from GitHub
    #   Processors::Route::VRS.import_airline('QFA')
    #
    # @example Import every airline from GitHub
    #   Processors::Route::VRS.import_all_from_github
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/routes/schema-01
    class VRS < Processors::Base
      # Raw content base for per-airline files (folder per first letter of the code).
      GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/routes/schema-01'

      # Raw content root of the repository, used to build URLs from API tree paths.
      GITHUB_RAW_ROOT = 'https://raw.githubusercontent.com/vradarserver/standing-data/main'

      # GitHub API endpoint listing the repository tree recursively.
      GITHUB_API_TREE = 'https://api.github.com/repos/vradarserver/standing-data/git/trees/main?recursive=1'

      # The STI type stored on every imported row.
      SOURCE_TYPE = 'Source::Route::VRSRouteSource'

      # The maximum split-file digit (files are named <CODE>-0.csv .. <CODE>-9.csv).
      MAX_SPLIT_DIGIT = 9

      # The number of records to accumulate before flushing to the database.
      BATCH_SIZE = 1000

      class << self
        # Imports all route CSV files from a local clone of the repository.
        #
        # @param directory_path [String] Path to the routes/schema-01 directory
        # @return [Hash] Combined import results
        def import(directory_path)
          raise ArgumentError, "Directory not found: #{directory_path}" unless File.directory?(directory_path)

          csv_files = Dir.glob(File.join(directory_path, '*', '*.csv')).sort
          raise ArgumentError, "No CSV files found in #{directory_path}" if csv_files.empty?

          # Capture results inside the block; with_bulk_import does not reliably
          # return the block's value (MeiliSearch's deactivate! returns its own).
          results = []
          with_bulk_import do
            results = csv_files.map do |path|
              import_csv_data(File.read(path, encoding: 'utf-8'), source_name: File.basename(path))
            end
          end

          finalise(results)
        end

        # Imports every route file discovered from the GitHub API tree.
        #
        # @param progress [Boolean] Whether to show a progress bar
        # @return [Hash] Combined import results
        def import_all_from_github(progress: true)
          paths = fetch_available_paths
          if paths.empty?
            Rails.logger.error 'Failed to discover route files from GitHub'
            return finalise([])
          end

          Rails.logger.info "Found #{paths.count} route files to import from VRS"
          progress_bar = progress ? create_progress_bar(paths.count) : nil

          # Capture results inside the block; with_bulk_import does not reliably
          # return the block's value (MeiliSearch's deactivate! returns its own).
          results = []
          with_bulk_import do
            results = paths.map do |path|
              body = get_source_from_url("#{GITHUB_RAW_ROOT}/#{path}")
              progress_bar&.increment!
              next if body.nil?

              import_csv_data(body, source_name: File.basename(path))
            end.compact
          end

          finalise(results)
        end

        # Imports a single airline's routes from GitHub.
        #
        # Tries the "<CODE>-all.csv" file first; if absent, tries the split files
        # "<CODE>-0.csv" .. "<CODE>-9.csv".
        #
        # @param code [String] The airline callsign code, e.g. "QFA"
        # @return [Hash] Combined import results
        def import_airline(code)
          code = code.to_s.strip.upcase
          letter = code[0]
          base = "#{GITHUB_RAW_BASE}/#{letter}"

          # Capture results inside the block; with_bulk_import does not reliably
          # return the block's value (MeiliSearch's deactivate! returns its own).
          results = []
          with_bulk_import do
            all_body = get_source_from_url("#{base}/#{code}-all.csv")
            results = if all_body
                        [import_csv_data(all_body, source_name: "#{code}-all.csv")]
                      else
                        (0..MAX_SPLIT_DIGIT).filter_map do |digit|
                          body = get_source_from_url("#{base}/#{code}-#{digit}.csv")
                          import_csv_data(body, source_name: "#{code}-#{digit}.csv") if body
                        end
                      end
          end

          finalise(results)
        end

        # Parses raw CSV content and upserts the rows into the source table.
        #
        # @param csv_data [String] The raw CSV content
        # @param source_name [String] A name for logging (usually the file name)
        # @return [Hash] Results with :success_count, :error_count and :errors
        def import_csv_data(csv_data, source_name:)
          success_count = 0
          errors = []
          pending = []
          timestamp = Time.current

          csv = CSV.parse(strip_bom(csv_data), headers: true)

          csv.each do |row|
            attributes = build_attributes(row, timestamp)

            if attributes.nil?
              errors << { source: source_name, row: row.to_h, error: 'Missing required field' }
              next
            end

            pending << attributes
            success_count += 1

            if pending.size >= BATCH_SIZE
              flush(pending)
              pending = []
            end
          end

          flush(pending)

          { success_count: success_count, error_count: errors.count, errors: errors }
        rescue CSV::MalformedCSVError => e
          Rails.logger.error "CSV parsing error in #{source_name}: #{e.message}"
          { success_count: 0, error_count: 1, errors: [{ source: source_name, error: e.message }] }
        end

        # Discovers the route CSV file paths from the GitHub API tree.
        #
        # @return [Array<String>] Repository-relative paths to route CSV files
        def fetch_available_paths
          response = get_source_from_url(
            GITHUB_API_TREE, 'GET',
            { 'Accept' => 'application/vnd.github.v3+json', 'User-Agent' => 'Aerodex-Route-Importer' }
          )
          return [] if response.nil?

          tree = JSON.parse(response)
          pattern = %r{\Aroutes/schema-01/[A-Z]/[A-Z0-9]+-(all|\d)\.csv\z}i

          tree['tree'].filter_map { |item| item['path'] if item['path'].match?(pattern) }.sort
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse GitHub API response: #{e.message}"
          []
        end

        private

        # Builds an attribute hash for one CSV row, or nil if a required field is missing.
        #
        # @param row [CSV::Row] The CSV row
        # @param timestamp [Time] The import batch timestamp
        # @return [Hash, nil] Attributes for upsert, or nil to skip the row
        def build_attributes(row, timestamp)
          callsign = row['Callsign']&.strip
          airline_code = row['AirlineCode']&.strip
          airport_codes = row['AirportCodes']&.strip

          return nil if callsign.blank? || airline_code.blank? || airport_codes.blank?

          {
            type: SOURCE_TYPE,
            callsign: callsign,
            airline_code: airline_code,
            airport_codes: airport_codes,
            data: { 'Code' => row['Code']&.strip, 'Number' => row['Number']&.strip }.compact,
            import_date: timestamp
          }
        end

        # Upserts a batch of attribute hashes into the source table.
        #
        # @param records [Array<Hash>] The attribute hashes to upsert
        def flush(records)
          return if records.empty?

          # Postgres rejects an INSERT ... ON CONFLICT that touches the same
          # conflict row twice in a single statement, so a batch containing two
          # rows with the same callsign would raise ActiveRecord::StatementInvalid.
          # The external source is not guaranteed to be free of duplicates, so
          # de-duplicate by callsign here, keeping the LAST occurrence to match
          # upsert "last wins" semantics. All rows share the same type
          # (SOURCE_TYPE), so de-duplicating by callsign alone is sufficient.
          deduplicated = records.each_with_object({}) do |record, acc|
            acc[record[:callsign]] = record
          end.values

          now = Time.current
          rows = deduplicated.map { |r| r.merge(created_at: now, updated_at: now) }

          Source::Route::VRSRouteSource.upsert_all(
            rows,
            unique_by: %i[callsign type],
            update_only: %i[airline_code airport_codes data import_date]
          )
        end

        # Removes a leading UTF-8 byte-order mark, if present.
        #
        # @param data [String] The raw content
        # @return [String] The content without a leading BOM
        def strip_bom(data)
          data.dup.force_encoding('UTF-8').sub(/\A\xEF\xBB\xBF/u, '')
        end

        # Aggregates per-file results and records an import report.
        #
        # @param results [Array<Hash>] Per-file results
        # @return [Hash] Combined results
        def finalise(results)
          combined = results.compact.each_with_object({ success_count: 0, error_count: 0, errors: [] }) do |r, acc|
            acc[:success_count] += r[:success_count]
            acc[:error_count] += r[:error_count]
            acc[:errors].concat(r[:errors])
          end

          new_import_report(combined[:errors], combined[:success_count] + combined[:error_count])
          combined
        end
      end
    end
  end
end
