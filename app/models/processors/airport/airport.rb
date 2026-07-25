# frozen_string_literal: true

module Processors
  module Airport
    # Processor for combining airport data from sources into canonical Airport records.
    #
    # Matches airports by ICAO code (primary) or IATA code (fallback).
    # Uses FieldMerger for trust-based field resolution when sources disagree.
    class Airport < Processors::Base
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Airport'

      # The fields to merge when combining sources.
      # Maps source field => canonical field (same name if not specified).
      # Timezone is handled separately via coordinate lookup, not merged from sources
      MERGE_FIELDS = %i[name city latitude longitude altitude].freeze

      # Source fields that map to different canonical field names
      SOURCE_FIELD_MAP = {
        altitude: :elevation # Sources use 'elevation', canonical uses 'altitude'
      }.freeze

      class << self
        # Combines a single airport by ICAO or IATA code.
        #
        # @param identifier [String] The ICAO or IATA code
        # @param by [Symbol] The identifier type (:icao or :iata). Default: auto-detect
        # @return [Hash] Result with :airport, :created, :updated, or :error
        #
        # @example By ICAO code
        #   result = Processors::Airport::Airport.combine_one("YSSY")
        #   result[:airport]  # => <Airport icao_code: "YSSY">
        #
        # @example By IATA code
        #   result = Processors::Airport::Airport.combine_one("SYD", by: :iata)
        def combine_one(identifier, by: nil)
          identifier = identifier.to_s.strip.upcase
          raise ArgumentError, 'Identifier is required' if identifier.blank?

          # Auto-detect identifier type if not specified
          by ||= identifier.length == 4 ? :icao : :iata

          # Gather sources for this airport
          sources = gather_sources_for_identifier(identifier, by)

          return { error: "No sources found for #{by}: #{identifier}" } if sources.empty?

          # Load caches for lookups
          preload_reference_data

          # Build the identifier key
          key = { type: by, code: identifier }
          conflicts = []
          result = merge_sources_for_airport(key, sources, conflicts)

          return { error: result[:error] } if result[:error]

          if result[:attributes].blank?
            airport = case by
                      when :icao then @airports_by_icao[identifier]
                      when :iata then @airports_by_iata[identifier]
                      end
            return { airport: airport, unchanged: true }
          end

          # Save the record
          if result[:new_record]
            ::Airport.insert_all([result[:attributes]])
            airport = by == :icao ? ::Airport.find_by(icao_code: identifier) : ::Airport.find_by(iata_code: identifier)
            { airport: airport, created: true, conflicts: conflicts }
          else
            ::Airport.upsert_all([result[:attributes]], unique_by: :id)
            airport = by == :icao ? ::Airport.find_by(icao_code: identifier) : ::Airport.find_by(iata_code: identifier)
            { airport: airport, updated: true, conflicts: conflicts }
          end
        ensure
          clear_caches
        end

        # Gathers all sources for a specific airport identifier.
        #
        # @param identifier [String] The ICAO or IATA code
        # @param by [Symbol] The identifier type (:icao or :iata)
        # @return [Array<ApplicationRecord>] All source records matching the identifier
        def gather_sources_for_identifier(identifier, by)
          sources = []
          field = by == :icao ? :icao_code : :iata_code

          sources.concat(Source::Airport::OurAirportsAirportSource.includable.where(field => identifier).to_a)
          sources.concat(Source::Airport::OpenFlightsAirportSource.includable.where(field => identifier).to_a)
          sources
        end

        # Combines airport data from all available sources into staged changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @return [StagedBatch] The batch containing staged changes
        def combine_sources(triggered_by: nil)
          with_staged_batch(entity_type: 'Airport', triggered_by: triggered_by) do
            preload_reference_data

            sources_by_identifier = group_sources_by_identifier
            conflicts = []

            progress_bar = create_progress_bar(sources_by_identifier.count)

            sources_by_identifier.each do |identifier, sources|
              merge_sources_for_airport_staged(identifier, sources, conflicts)
              progress_bar.increment!
            end

            # Log any conflicts for review
            log_conflicts(conflicts) if conflicts.any?

            # Store conflict count in batch notes if any
            if conflicts.any?
              current_batch.notes ||= ''
              current_batch.notes += "Processing completed with #{conflicts.count} field conflicts\n"
            end
          end
        ensure
          clear_caches
        end

        # Preloads all reference data needed for combining into memory.
        def preload_reference_data
          @countries_by_code = ::Country.all.index_by(&:iso_2char_code)
          @airports_by_icao = ::Airport.where.not(icao_code: nil).index_by(&:icao_code)
          @airports_by_iata = ::Airport.where(icao_code: nil).where.not(iata_code: nil).index_by(&:iata_code)

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)
        end

        # Clears all cached data after processing.
        def clear_caches
          @countries_by_code = nil
          @airports_by_icao = nil
          @airports_by_iata = nil
        end

        private

        # Groups all source records by their best identifier (ICAO preferred, then IATA).
        #
        # Uses a composite key of (identifier_type, identifier_value) to handle
        # airports that only have IATA codes.
        #
        # @return [Hash<Hash, Array>] Sources grouped by identifier
        def group_sources_by_identifier
          sources = {}

          # Process OurAirports sources (higher trust, more complete)
          Source::Airport::OurAirportsAirportSource.includable.find_each do |source|
            key = identifier_key_for(source)
            next if key.nil?

            sources[key] ||= []
            sources[key] << source
          end

          # Process OpenFlights sources
          Source::Airport::OpenFlightsAirportSource.includable.find_each do |source|
            key = identifier_key_for(source)
            next if key.nil?

            sources[key] ||= []
            sources[key] << source
          end

          sources
        end

        # Returns a unique identifier key for the source.
        # Prefers ICAO code, falls back to IATA code.
        #
        # @param source [AirportSource] The source record
        # @return [Hash, nil] The identifier key or nil if no valid identifier
        def identifier_key_for(source)
          if source.icao_code.present?
            { type: :icao, code: source.icao_code }
          elsif source.iata_code.present?
            { type: :iata, code: source.iata_code }
          end
        end

        # Merges sources for a single airport and stages the change.
        #
        # @param identifier [Hash] The identifier key (:type and :code)
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :record, or :error key
        def merge_sources_for_airport_staged(identifier, sources, conflicts)
          # Link to country first - skip if no valid country (required field)
          country = find_country_for_sources(sources)
          unless country
            current_batch.notes ||= ''
            current_batch.notes += "Error: No valid country found for airport #{identifier[:code]}\n"
            return { error: "No valid country found for airport #{identifier[:code]}" }
          end

          record = find_or_initialize_airport(identifier, sources)
          is_new_record = record.new_record?

          record.country_id = country.id

          # Set ICAO and IATA codes from sources
          set_airport_codes(record, sources)

          # Build merged values and track provenance info
          provenance_updates = []
          MERGE_FIELDS.each do |field|
            source_field = source_field_for(field)
            merger = FieldMerger.new(sources: sources, field: source_field, entity_type: ENTITY_TYPE)

            record.public_send("#{field}=", merger.best_value)

            if merger.best_source && merger.best_value.present?
              provenance_updates << { field: field, source: merger.best_source, confidence: merger.best_confidence }
            end

            next unless merger.has_conflict?

            conflict = merger.conflict_details
            conflict[:identifier] = identifier[:code] if conflict
            conflicts << conflict
          end

          # Calculate timezone from coordinates using WhereTZ for accuracy.
          set_timezone_from_coordinates(record)

          # Check for meaningful changes (content fields, not just metadata like provenance)
          meaningful_changes = record.changes.keys - %w[field_provenance last_combined_at]

          human_identifier = record.icao_code || record.iata_code

          if is_new_record
            # Set provenance for new records
            provenance_updates.each do |update|
              record.set_provenance(update[:field], source: update[:source], confidence: update[:confidence])
            end
            record.last_combined_at = Time.current
            stage_change(record, operation: :create, identifier: human_identifier)
            { record: record, created: true }
          elsif meaningful_changes.any?
            # Set provenance for updated records
            provenance_updates.each do |update|
              record.set_provenance(update[:field], source: update[:source], confidence: update[:confidence])
            end
            record.last_combined_at = Time.current
            stage_change(record, operation: :update, identifier: human_identifier)
            { record: record, updated: true }
          else
            current_batch.summary['unchanged'] += 1
            { record: record, unchanged: true }
          end
        end

        # Merges sources for a single airport and returns attributes for batch processing.
        # Used by combine_one for direct saves.
        #
        # @param identifier [Hash] The identifier key (:type and :code)
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :attributes and :new_record, or :error key
        def merge_sources_for_airport(identifier, sources, conflicts)
          # Link to country first - skip if no valid country (required field)
          country = find_country_for_sources(sources)
          unless country
            return {
              error: {
                identifier: identifier,
                source_count: sources.count,
                errors: ['No valid country found for airport']
              }
            }
          end

          record = find_or_initialize_airport(identifier, sources)
          is_new_record = record.new_record?

          record.country_id = country.id

          # Set ICAO and IATA codes from sources
          set_airport_codes(record, sources)

          # Build merged values and track provenance info
          provenance_updates = []
          MERGE_FIELDS.each do |field|
            source_field = source_field_for(field)
            merger = FieldMerger.new(sources: sources, field: source_field, entity_type: ENTITY_TYPE)

            record.public_send("#{field}=", merger.best_value)

            if merger.best_source && merger.best_value.present?
              provenance_updates << { field: field, source: merger.best_source, confidence: merger.best_confidence }
            end

            next unless merger.has_conflict?

            conflict = merger.conflict_details
            conflict[:identifier] = identifier[:code] if conflict
            conflicts << conflict
          end

          # Calculate timezone from coordinates using WhereTZ for accuracy.
          # Source timezone data is often incorrect (e.g. Melbourne having Australia/Hobart),
          # so we derive it from the coordinates which are more reliable.
          set_timezone_from_coordinates(record)

          # Check for meaningful changes BEFORE setting provenance
          has_changes = is_new_record || record.changes.any?

          unless has_changes
            # No changes needed
            return {}
          end

          # Set provenance for changed fields
          provenance_updates.each do |update|
            record.set_provenance(update[:field], source: update[:source], confidence: update[:confidence])
          end

          record.last_combined_at = Time.current

          # Return attributes for batch processing
          {
            attributes: is_new_record ? record_to_insert_attributes(record) : record_to_update_attributes(record),
            new_record: is_new_record
          }
        end

        # Converts a record to a hash of attributes for batch insert (new records).
        #
        # @param record [Airport] The airport record
        # @return [Hash] Attributes hash (without id - let PostgreSQL generate it)
        def record_to_insert_attributes(record)
          now = Time.current
          {
            icao_code: record.icao_code,
            iata_code: record.iata_code,
            name: record.name,
            city: record.city,
            latitude: record.latitude,
            longitude: record.longitude,
            altitude: record.altitude,
            timezone: record.timezone,
            country_id: record.country_id,
            field_provenance: record.field_provenance,
            last_combined_at: record.last_combined_at,
            created_at: now,
            updated_at: now
          }
        end

        # Converts a record to a hash of attributes for batch update (existing records).
        #
        # @param record [Airport] The airport record
        # @return [Hash] Attributes hash (with id for upsert matching)
        def record_to_update_attributes(record)
          now = Time.current
          {
            id: record.id,
            icao_code: record.icao_code,
            iata_code: record.iata_code,
            name: record.name,
            city: record.city,
            latitude: record.latitude,
            longitude: record.longitude,
            altitude: record.altitude,
            timezone: record.timezone,
            country_id: record.country_id,
            field_provenance: record.field_provenance,
            last_combined_at: record.last_combined_at,
            updated_at: now
          }
        end

        # Flushes pending inserts to the database in a batch.
        #
        # @param records [Array<Hash>] Array of attribute hashes
        def flush_inserts(records)
          return if records.empty?

          ::Airport.insert_all(records)
        end

        # Flushes pending updates to the database in a batch.
        #
        # @param records [Array<Hash>] Array of attribute hashes
        def flush_updates(records)
          return if records.empty?

          ::Airport.upsert_all(records, unique_by: :id)
        end

        def find_or_initialize_airport(identifier, _sources)
          case identifier[:type]
          when :icao
            existing = @airports_by_icao[identifier[:code]]
            if existing
              existing
            else
              new_airport = ::Airport.new(icao_code: identifier[:code])
              @airports_by_icao[identifier[:code]] = new_airport
              new_airport
            end
          when :iata
            existing = @airports_by_iata[identifier[:code]]
            if existing
              existing
            else
              new_airport = ::Airport.new(iata_code: identifier[:code])
              @airports_by_iata[identifier[:code]] = new_airport
              new_airport
            end
          end
        end

        def set_airport_codes(record, sources)
          # Collect all codes from sources
          icao_codes = sources.filter_map(&:icao_code).uniq
          iata_codes = sources.filter_map(&:iata_code).uniq

          # Set ICAO code (should be consistent if present)
          record.icao_code = icao_codes.first if icao_codes.any?

          # Set IATA code (should be consistent if present)
          record.iata_code = iata_codes.first if iata_codes.any?
        end

        # Finds the country for the given sources using preloaded country cache.
        #
        # @param sources [Array] The source records
        # @return [Country, nil] The country or nil if not found
        def find_country_for_sources(sources)
          country_code = sources.find { |s| s.country_code.present? }&.country_code
          return nil unless country_code

          @countries_by_code[country_code]
        end

        def log_conflicts(conflicts)
          Rails.logger.info "Airport combine completed with #{conflicts.count} field conflicts"

          # Print formatted conflicts to console
          ConflictFormatter.print_grouped_by_identifier(conflicts)

          # Also log the summary
          Rails.logger.info ConflictFormatter.summary(conflicts)
        end

        # Maps a canonical field name to the corresponding source field name.
        # Handles cases where source models use different field names than the canonical model.
        #
        # @param canonical_field [Symbol] The canonical field name
        # @return [Symbol] The source field name
        def source_field_for(canonical_field)
          # Check explicit field mapping first
          return SOURCE_FIELD_MAP[canonical_field] if SOURCE_FIELD_MAP.key?(canonical_field)

          # Special case: sources use location_name method for city
          return :location_name if canonical_field == :city

          # Default: source field name matches canonical field name
          canonical_field
        end

        # Confidence score for timezone derived from coordinates.
        # High confidence as OSM data is well-maintained and coordinates are reliable.
        TIMEZONE_CONFIDENCE = 90

        # Sets the timezone for an airport based on its coordinates using WhereTZ.
        # This is more accurate than source data which can have incorrect timezones.
        #
        # Skips lookup if coordinates haven't changed and we already have a timezone.
        #
        # @param record [Airport] The airport record to update
        def set_timezone_from_coordinates(record)
          return if record.latitude.blank? || record.longitude.blank?

          # Skip expensive WhereTZ lookup if coordinates unchanged and we have a timezone
          coords_changed = record.latitude_changed? || record.longitude_changed?
          return if !coords_changed && record.timezone.present? && !record.new_record?

          timezone = ::WhereTZ.lookup(record.latitude, record.longitude)

          # WhereTZ can return an array for points near timezone boundaries - take the first
          timezone = timezone.first if timezone.is_a?(Array)

          return if timezone.blank?

          record.timezone = timezone
          record.set_derived_provenance(
            :timezone,
            source_name: HasFieldProvenance::TIMEZONE_BOUNDARY_SOURCE,
            confidence: TIMEZONE_CONFIDENCE
          )
        rescue StandardError => e
          # Log error but don't fail the import - timezone is not critical
          Rails.logger.warn "WhereTZ lookup failed for airport #{record.icao_code || record.iata_code}: #{e.message}"
        end
      end
    end
  end
end
