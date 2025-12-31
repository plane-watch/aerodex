# frozen_string_literal: true

module Processors
  module AircraftType
    # Processor for combining aircraft type data from sources into canonical AircraftType records.
    #
    # Uses FieldMerger for consistent source handling, even with a single source currently.
    # This makes adding additional sources straightforward in the future.
    #
    # Name canonicalization is used to merge duplicates like "An-148" and "Antonov An-148"
    # while keeping legitimately different variants separate (737-700 vs 737-800).
    class AircraftType < Processors::Base
      extend AircraftTypeNameCanonicalisation

      # The entity type for trust score lookups
      ENTITY_TYPE = 'AircraftType'

      # The fields to merge when combining sources.
      # Note: type_code and name are part of the grouping key, so they're not merged.
      MERGE_FIELDS = %i[wtc engines engine_type].freeze

      # Batch size for bulk insert/update operations
      BATCH_SIZE = 1000

      class << self
        # Combines a single aircraft type by type code and optional name.
        #
        # @param type_code [String] The ICAO type designator (e.g., "B738")
        # @param name [String, nil] The variant name (e.g., "Boeing 737-800"). If nil, combines all variants.
        # @return [Hash] Result with :aircraft_type(s), :created, :updated, or :error
        #
        # @example Combine a specific variant
        #   result = Processors::AircraftType::AircraftType.combine_one("B738", "Boeing 737-800")
        #   result[:aircraft_type]  # => <AircraftType type_code: "B738", name: "Boeing 737-800">
        #
        # @example Combine all variants of a type code
        #   result = Processors::AircraftType::AircraftType.combine_one("B738")
        #   result[:aircraft_types]  # => [<AircraftType>, <AircraftType>, ...]
        def combine_one(type_code, name = nil)
          type_code = type_code.to_s.strip.upcase
          raise ArgumentError, "Type code is required" if type_code.blank?

          # Gather sources for this type code (and optionally name)
          sources_grouped = gather_sources_for_type_code(type_code, name)

          if sources_grouped.empty?
            return { error: "No sources found for type code: #{type_code}#{name ? " / #{name}" : ''}" }
          end

          # Load caches for lookups
          preload_reference_data

          results = []
          conflicts = []

          sources_grouped.each do |key, sources|
            tc, nm = key
            result = merge_sources_for_variant(tc, nm, sources, conflicts)

            next if result[:attributes].blank?

            if result[:new_record]
              ::AircraftType.insert_all([result[:attributes]])
              aircraft_type = ::AircraftType.find_by(type_code: tc, name: nm)
              results << { aircraft_type: aircraft_type, created: true }
            else
              ::AircraftType.upsert_all([result[:attributes]], unique_by: :id)
              aircraft_type = ::AircraftType.find_by(type_code: tc, name: nm)
              results << { aircraft_type: aircraft_type, updated: true }
            end
          end

          if name
            # Single variant requested
            results.first || { unchanged: true }
          else
            # Multiple variants
            { aircraft_types: results, conflicts: conflicts }
          end
        ensure
          clear_caches
        end

        # Gathers sources for a type code (and optionally a specific name).
        #
        # @param type_code [String] The ICAO type designator
        # @param name [String, nil] Optional variant name
        # @return [Hash] Sources grouped by [type_code, name]
        def gather_sources_for_type_code(type_code, name = nil)
          sources = {}

          [Source::AircraftType::CfappsICAOIntAircraftTypeSource,
           Source::AircraftType::OpenFlightsAircraftTypeSource,
           Source::AircraftType::VRSAircraftTypeSource].each do |klass|
            next unless defined?(klass)

            scope = klass.includable.where(type_code: type_code)
            scope = scope.where(name: name) if name.present?

            scope.find_each do |source|
              key = [source.type_code, source.name]
              sources[key] ||= []
              sources[key] << source
            end
          end

          sources
        end

        # Combines aircraft type data from all available sources into canonical AircraftType records.
        # Groups sources by (type_code, name) to preserve variant information.
        #
        # @return [Array<Hash>, true] Returns array of errors if any, otherwise true
        def combine_sources
          preload_reference_data

          grouped_sources = group_sources_by_type_code_and_name
          errors = []
          conflicts = []
          pending_inserts = []
          pending_updates = []

          progress_bar = create_progress_bar(grouped_sources.count)

          with_bulk_import do
            grouped_sources.each do |key, sources|
              type_code, name = key
              result = merge_sources_for_variant(type_code, name, sources, conflicts)

              if result[:error]
                errors << result[:error]
              elsif result[:attributes]
                if result[:new_record]
                  pending_inserts << result[:attributes]
                else
                  pending_updates << result[:attributes]
                end
              end

              progress_bar.increment!

              # Flush batches periodically
              if pending_inserts.size >= BATCH_SIZE
                flush_inserts(pending_inserts)
                pending_inserts.clear
              end
              if pending_updates.size >= BATCH_SIZE
                flush_updates(pending_updates)
                pending_updates.clear
              end
            end

            # Flush remaining records
            flush_inserts(pending_inserts) if pending_inserts.any?
            flush_updates(pending_updates) if pending_updates.any?
          end

          # Log any conflicts for review
          log_conflicts(conflicts) if conflicts.any?

          # Reindex and reset counter caches
          finalize_combine(
            ::AircraftType,
            counter_caches: { ::Manufacturer => :aircraft_types_count }
          )

          # Create an import report
          new_import_report(errors, grouped_sources.count)

          errors.any? ? errors : true
        ensure
          clear_caches
        end

        # Preloads all reference data needed for combining into memory.
        def preload_reference_data
          # Preload all manufacturers by ICAO code
          @manufacturers_by_code = ::Manufacturer.where.not(icao_code: nil).index_by(&:icao_code)

          # Preload existing aircraft types by (type_code, name) for variant-level matching
          @aircraft_types_cache = {}
          ::AircraftType.find_each do |at|
            key = "#{at.type_code}:#{at.name}"
            @aircraft_types_cache[key] = at
          end

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)
        end

        # Clears all cached data after processing.
        def clear_caches
          @manufacturers_by_code = nil
          @aircraft_types_cache = nil
        end

        private

        # Groups all source records by their (type_code, canonical_name_key).
        # Uses name canonicalization to merge duplicates like "An-148" and "Antonov An-148".
        # The best name is selected from all sources in each group.
        #
        # @return [Hash<Array, Hash>] Sources grouped by [type_code, best_name]
        #   Each value is { sources: [...], all_names: [...] }
        def group_sources_by_type_code_and_name
          # First pass: group by (type_code, canonical_key)
          by_canonical = Hash.new { |h, k| h[k] = { sources: [], all_names: Set.new } }

          source_classes = [
            Source::AircraftType::CfappsICAOIntAircraftTypeSource,
            Source::AircraftType::OpenFlightsAircraftTypeSource,
            Source::AircraftType::VRSAircraftTypeSource
          ]

          source_classes.each do |klass|
            klass.includable.find_each do |source|
              next if source.type_code.blank? || source.name.blank?

              canonical_key = canonical_name_key(source.name)
              group_key = [source.type_code, canonical_key]

              by_canonical[group_key][:sources] << source
              by_canonical[group_key][:all_names] << source.name
            end
          end

          # Second pass: split groups where names represent genuinely different variants
          # and select the best name for each group
          final_groups = {}

          by_canonical.each do |(type_code, _canonical_key), data|
            names = data[:all_names].to_a
            sources = data[:sources]

            # Check if any names in this group are genuinely different variants
            variant_groups = group_by_variant(names)

            variant_groups.each do |variant_names|
              # Get sources for this variant
              variant_sources = sources.select { |s| variant_names.include?(s.name) }
              next if variant_sources.empty?

              # Pick the best name for this variant
              best_name = best_name_from(variant_names)
              final_key = [type_code, best_name]

              final_groups[final_key] ||= []
              final_groups[final_key].concat(variant_sources)
            end
          end

          final_groups
        end

        # Groups names into sets of genuinely different variants.
        # Names that are just spelling/format variations go in the same group.
        #
        # @param names [Array<String>] List of names to group
        # @return [Array<Array<String>>] Groups of related names
        def group_by_variant(names)
          return [names] if names.size <= 1

          # Start with each name in its own group
          groups = names.map { |n| [n] }

          # Merge groups where names are NOT different variants
          merged = true
          while merged
            merged = false
            groups.combination(2).each do |group1, group2|
              # Check if any pair across groups are NOT different variants
              should_merge = group1.product(group2).any? do |name1, name2|
                !different_variants?(name1, name2)
              end

              if should_merge
                group1.concat(group2)
                groups.delete(group2)
                merged = true
                break
              end
            end
          end

          groups
        end

        # Merges sources for a single (type_code, name) variant and returns attributes for batching.
        #
        # @param type_code [String] The aircraft type code
        # @param name [String] The aircraft variant name
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :attributes and :new_record, or :error key
        def merge_sources_for_variant(type_code, name, sources, conflicts)
          # Find existing record from cache using (type_code, name) as the key
          cache_key = "#{type_code}:#{name}"
          record = @aircraft_types_cache[cache_key]

          if record.nil?
            record = ::AircraftType.new(type_code: type_code, name: name)
            @aircraft_types_cache[cache_key] = record
          end

          is_new_record = record.new_record?

          # Pick manufacturer using FieldMerger for consistency with other fields
          manufacturer_merger = FieldMerger.new(sources: sources, field: :manufacturer, entity_type: ENTITY_TYPE)
          manufacturer_code = manufacturer_merger.best_value
          manufacturer = find_or_create_manufacturer(manufacturer_code)
          record.manufacturer = manufacturer

          if manufacturer_merger.has_conflict?
            conflict = manufacturer_merger.conflict_details
            conflict[:identifier] = "#{type_code} - #{name}"
            conflicts << conflict
          end

          # Build merged values for remaining fields and track provenance info
          provenance_updates = []

          # Track provenance for the key fields (type_code, name) from first source
          first_source = sources.first
          provenance_updates << { field: :type_code, source: first_source, confidence: 100 }
          provenance_updates << { field: :name, source: first_source, confidence: 100 }

          if manufacturer_merger.best_source && manufacturer_code.present?
            provenance_updates << { field: :manufacturer, source: manufacturer_merger.best_source,
                                    confidence: manufacturer_merger.best_confidence }
          end

          # Merge remaining fields (wtc, engines, engine_type)
          MERGE_FIELDS.each do |field|
            merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

            record.public_send("#{field}=", merger.best_value)

            if merger.best_source && merger.best_value.present?
              provenance_updates << { field: field, source: merger.best_source, confidence: merger.best_confidence }
            end

            if merger.has_conflict?
              conflict = merger.conflict_details
              conflict[:identifier] = "#{type_code} - #{name}"
              conflicts << conflict
            end
          end

          # Check for changes BEFORE setting provenance
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
        # @param record [AircraftType] The aircraft type record
        # @return [Hash] Attributes hash (without id - let PostgreSQL generate it)
        def record_to_insert_attributes(record)
          now = Time.current
          {
            type_code: record.type_code,
            name: record.name,
            manufacturer_id: record.manufacturer_id,
            wtc: record.wtc,
            engines: record.engines,
            engine_type: record.engine_type,
            category: record.category,
            field_provenance: record.field_provenance,
            last_combined_at: record.last_combined_at,
            created_at: now,
            updated_at: now
          }
        end

        # Converts a record to a hash of attributes for batch update (existing records).
        #
        # @param record [AircraftType] The aircraft type record
        # @return [Hash] Attributes hash (with id for upsert matching)
        def record_to_update_attributes(record)
          now = Time.current
          {
            id: record.id,
            type_code: record.type_code,
            name: record.name,
            manufacturer_id: record.manufacturer_id,
            wtc: record.wtc,
            engines: record.engines,
            engine_type: record.engine_type,
            category: record.category,
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

          ::AircraftType.insert_all(records)
        end

        # Flushes pending updates to the database in a batch.
        #
        # @param records [Array<Hash>] Array of attribute hashes
        def flush_updates(records)
          return if records.empty?

          ::AircraftType.upsert_all(records, unique_by: :id)
        end

        # Finds an existing manufacturer by ICAO code, or creates a stub if missing.
        # Stub manufacturers are marked with provenance indicating they were auto-generated.
        #
        # @param icao_code [String] The manufacturer ICAO code
        # @return [::Manufacturer] The found or created manufacturer
        def find_or_create_manufacturer(icao_code)
          return nil if icao_code.blank?

          # Check cache first
          manufacturer = @manufacturers_by_code[icao_code]
          return manufacturer if manufacturer

          # Create a stub manufacturer with a name derived from the ICAO code
          # Mark it with provenance so we know it was auto-generated
          name = humanise_manufacturer_code(icao_code)

          manufacturer = ::Manufacturer.new(
            icao_code: icao_code,
            name: name,
            field_provenance: {
              'name' => {
                'source_type' => HasFieldProvenance::AUTO_GENERATED_SOURCE,
                'source_id' => nil,
                'confidence' => 0,
                'combined_at' => Time.current.iso8601,
                'note' => 'Stub manufacturer created during AircraftType import - needs enrichment'
              },
              'icao_code' => {
                'source_type' => 'CfappsICAOIntAircraftTypeSource',
                'source_id' => nil,
                'confidence' => 100,
                'combined_at' => Time.current.iso8601
              }
            }
          )
          manufacturer.save!

          # Add to cache for subsequent lookups
          @manufacturers_by_code[icao_code] = manufacturer

          Rails.logger.info "Created stub manufacturer: #{icao_code} => #{name}"
          manufacturer
        end

        # Converts a manufacturer ICAO code to a human-readable name.
        # E.g., "BELL-BOEING" => "Bell-Boeing", "A2 CZ" => "A2 CZ"
        #
        # @param code [String] The ICAO code
        # @return [String] A human-readable name
        def humanise_manufacturer_code(code)
          # Handle joint ventures (BELL-BOEING => Bell-Boeing)
          if code.include?('-')
            code.split('-').map(&:titleize).join('-')
          # Handle codes with spaces (already readable)
          elsif code.include?(' ')
            code.split.map { |word| word.length <= 3 ? word : word.titleize }.join(' ')
          # Handle short codes (keep as-is, likely acronyms)
          elsif code.length <= 4
            code
          # Default: titleize
          else
            code.titleize
          end
        end

        # Logs conflict information for later review.
        #
        # @param conflicts [Array<Hash>] The conflicts to log
        def log_conflicts(conflicts)
          Rails.logger.info "AircraftType combine completed with #{conflicts.count} field conflicts"

          # Print formatted conflicts to console
          ConflictFormatter.print_grouped_by_identifier(conflicts)

          # Also log the summary
          Rails.logger.info ConflictFormatter.summary(conflicts)
        end
      end
    end
  end
end