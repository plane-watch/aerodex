# frozen_string_literal: true

module Processors
  module Aircraft
    # Processor for combining aircraft data from sources into canonical Aircraft records.
    #
    # Uses FieldMerger for consistent source handling across multiple sources
    # (CASA, CAANZ, and potentially others in the future).
    class Aircraft < Processors::Aircraft::Base
      extend BusinessNameNormalisation
      extend AircraftModelNormalisation
      extend OperatorNameCanonicalisation
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Aircraft'

      # The fields to merge when combining sources
      MERGE_FIELDS = %i[
        icao
        registration
        serial_number
        model
        owner
        engine_count
        engine_model
        registration_date
      ].freeze

      # Batch size for bulk insert/update operations
      BATCH_SIZE = 1000

      class << self
        # Combines a single aircraft by ICAO hex code.
        #
        # @param icao [String] The Mode S hex code (e.g., "7C1469")
        # @return [Hash] Result with :aircraft, :created, :updated, or :error
        #
        # @example
        #   result = Processors::Aircraft::Aircraft.combine_one("7C1469")
        #   result[:aircraft]  # => <Aircraft icao: "7C1469">
        #   result[:updated]   # => true
        def combine_one(icao)
          icao = icao.to_s.upcase.strip
          raise ArgumentError, "ICAO code is required" if icao.blank?

          # Gather sources for this specific ICAO
          sources = gather_sources_for_icao(icao)

          if sources.empty?
            return { error: "No sources found for ICAO: #{icao}" }
          end

          # Load caches (for lookups)
          load_lookup_caches

          conflicts = []
          result = merge_sources_for_icao(icao, sources, conflicts)

          if result[:error]
            return { error: result[:error] }
          end

          if result[:attributes].blank?
            # No changes needed
            aircraft = @aircraft_cache[icao]
            return { aircraft: aircraft, unchanged: true }
          end

          # Save the record
          if result[:new_record]
            ::Aircraft.insert_all([result[:attributes]])
            aircraft = ::Aircraft.find_by(icao: icao)
            { aircraft: aircraft, created: true }
          else
            ::Aircraft.upsert_all([result[:attributes]], unique_by: :id)
            aircraft = ::Aircraft.find_by(icao: icao)
            { aircraft: aircraft, updated: true }
          end
        ensure
          clear_caches
        end

        # Gathers all sources for a specific ICAO code.
        #
        # @param icao [String] The Mode S hex code
        # @return [Array<ApplicationRecord>] All source records for this ICAO
        def gather_sources_for_icao(icao)
          sources = []
          sources.concat(Source::Aircraft::CASAAircraftSource.includable.where(icao: icao).to_a)
          sources.concat(Source::Aircraft::CAANZAircraftSource.includable.where(icao: icao).to_a)
          sources.concat(Source::Aircraft::VRSAircraftSource.includable.where(icao: icao).to_a)
          sources.concat(Source::Aircraft::OpenskyAircraftSource.includable.where(icao: icao).to_a)
          sources
        end

        # Combines aircraft data from all available sources into canonical Aircraft records.
        #
        # @return [Array<Hash>, true] Returns array of errors if any, otherwise true
        def combine_sources
          # Collect all sources grouped by icao (the unique identifier)
          sources_by_icao = group_sources_by_icao
          errors = []
          conflicts = []
          pending_inserts = []
          pending_updates = []

          # Pre-load lookup caches to avoid N+1 queries
          load_lookup_caches

          progress_bar = create_progress_bar(sources_by_icao.count)

          with_bulk_import do
            sources_by_icao.each do |icao, sources|
              result = merge_sources_for_icao(icao, sources, conflicts)

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
            ::Aircraft,
            counter_caches: {
              ::Operator => :aircraft_count,
              ::AircraftType => :aircraft_count
            }
          )

          # Create an import report
          new_import_report(errors, sources_by_icao.count)

          errors.any? ? errors : true
        ensure
          clear_caches
        end

        private

        # Clears all cached data after processing.
        def clear_caches
          @aircraft_types_by_code_and_name = nil
          @aircraft_types_by_code = nil
          @countries_by_iso = nil
          @operators_by_icao = nil
          @operators_by_name = nil
          @operators_by_normalised_name = nil
          @aircraft_cache = nil
        end

        # Pre-loads lookup tables into memory to avoid N+1 queries.
        def load_lookup_caches
          # Cache aircraft types by (type_code, name) for exact variant matching,
          # and group by type_code for fallback matching
          @aircraft_types_by_code_and_name = {}
          @aircraft_types_by_code = Hash.new { |h, k| h[k] = [] }

          ::AircraftType.find_each do |at|
            key = "#{at.type_code}:#{at.name}"
            @aircraft_types_by_code_and_name[key] = at
            @aircraft_types_by_code[at.type_code] << at
          end

          @countries_by_iso = ::Country.all.index_by(&:iso_2char_code)
          @operators_by_icao = ::Operator.where.not(icao_code: [nil, '']).index_by(&:icao_code)
          @operators_by_name = ::Operator.all.index_by { |o| o.name.downcase }

          # Build a normalised name cache for fuzzy matching
          # (strips corporate suffixes and airline terms like "Airlines", "International", etc.)
          @operators_by_normalised_name = {}
          ::Operator.find_each do |op|
            normalised_key = aggressive_canonical_key(op.name)
            @operators_by_normalised_name[normalised_key] = op if normalised_key.present?
          end

          # Preload existing aircraft by icao for O(1) lookups
          @aircraft_cache = {}
          ::Aircraft.find_each do |aircraft|
            @aircraft_cache[aircraft.icao] = aircraft
          end

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)
        end

        # Groups all source records by their icao code.
        #
        # @return [Hash<String, Array>] Sources grouped by icao
        def group_sources_by_icao
          sources = {}

          # Add CASA sources (Australian civil aviation authority)
          Source::Aircraft::CASAAircraftSource.includable.find_each do |source|
            key = source.icao
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          # Add CAANZ sources (New Zealand civil aviation authority)
          Source::Aircraft::CAANZAircraftSource.includable.find_each do |source|
            key = source.icao
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          # Add VRS sources (crowdsourced global data)
          Source::Aircraft::VRSAircraftSource.includable.find_each do |source|
            key = source.icao
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          # Add OpenSky sources (crowdsourced, good owner data)
          Source::Aircraft::OpenskyAircraftSource.includable.find_each do |source|
            key = source.icao
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          sources
        end

        # Merges sources for a single icao and returns attributes for batch processing.
        #
        # @param icao [String] The Mode S hex code
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :attributes and :new_record, or :error key
        def merge_sources_for_icao(icao, sources, conflicts)
          # Find existing record from cache or initialize a new one
          record = @aircraft_cache[icao]
          if record.nil?
            record = ::Aircraft.new(icao: icao)
            @aircraft_cache[icao] = record
          end

          is_new_record = record.new_record?
          provenance_updates = []

          # Merge each field using FieldMerger
          MERGE_FIELDS.each do |field|
            merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

            record.public_send("#{field}=", merger.best_value)

            # Track provenance for this field
            if merger.best_source && merger.best_value.present?
              provenance_updates << { field: field, source: merger.best_source, confidence: merger.best_confidence }
            end

            # Collect conflict information for logging
            if merger.has_conflict?
              conflict = merger.conflict_details
              conflict[:identifier] = icao
              conflicts << conflict
            end
          end

          # Handle related records separately (require lookups, not simple field merge)
          # Note: assign_operator may create new operators synchronously (needs IDs)
          assign_aircraft_type(record, sources)
          assign_operator(record, sources)
          assign_registration_country(record, sources)

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

          # Validate before returning for batch processing
          unless record.valid?
            return {
              error: {
                icao: icao,
                source_count: sources.count,
                errors: record.errors.full_messages
              }
            }
          end

          # Return attributes for batch processing
          {
            attributes: is_new_record ? record_to_insert_attributes(record) : record_to_update_attributes(record),
            new_record: is_new_record
          }
        end

        # Assigns the aircraft type to an aircraft based on source data.
        # Attempts to match the specific variant using model name, with fallback to type_code only.
        #
        # Matching strategy:
        # 1. Exact match on (type_code, model) - best case
        # 2. Partial match - source model contained in AircraftType name or vice versa
        # 3. Fallback - any AircraftType with the type_code (picks first)
        #
        # @param record [::Aircraft] The aircraft record
        # @param sources [Array] The source records
        def assign_aircraft_type(record, sources)
          # Find the highest-trust source with a type code
          source_with_type = sources
            .select { |s| s.type_code.present? }
            .max_by { |s| TrustCalculator.new(s, field: :type_code, entity_type: ENTITY_TYPE).calculate }

          return unless source_with_type

          type_code = source_with_type.type_code
          model = source_with_type.model

          aircraft_type = find_best_aircraft_type_match(type_code, model)
          record.aircraft_type = aircraft_type if aircraft_type.present?
        end

        # Finds the best matching AircraftType for a given type_code and model.
        #
        # Matching strategy:
        # 1. Exact match on (type_code, model)
        # 2. Exact match using normalised base model (737-8SA → 737-800)
        # 3. Partial match - model contained in AircraftType name or vice versa
        # 4. Normalised partial match - base model matches AircraftType name
        # 5. Smart fallback - best commercial variant for the type_code
        #
        # @param type_code [String] The ICAO type designator
        # @param model [String, nil] The specific model/variant name from the source
        # @return [::AircraftType, nil]
        def find_best_aircraft_type_match(type_code, model)
          # Strategy 1: Exact match on (type_code, name)
          if model.present?
            exact_key = "#{type_code}:#{model}"
            return @aircraft_types_by_code_and_name[exact_key] if @aircraft_types_by_code_and_name[exact_key]
          end

          # Get all variants for this type_code
          variants = @aircraft_types_by_code[type_code]
          return nil if variants.empty?

          # Normalise model to base designation (e.g., 737-8SA → 737-800)
          base_model = model.present? ? normalise_to_base_model(model) : nil

          # Strategy 2: Exact match using normalised base model
          if base_model.present?
            exact_key = "#{type_code}:#{base_model}"
            return @aircraft_types_by_code_and_name[exact_key] if @aircraft_types_by_code_and_name[exact_key]
          end

          # Strategy 3: Partial match - model contained in variant name or vice versa
          # Exclude non-commercial variants (BBJ, ACJ, military) from partial matching
          commercial_variants = variants.reject { |at| non_commercial_variant?(at.name) }

          if model.present?
            model_downcase = model.downcase
            partial_match = commercial_variants.find do |at|
              name_downcase = at.name&.downcase || ''
              name_downcase.include?(model_downcase) || model_downcase.include?(name_downcase)
            end
            return partial_match if partial_match
          end

          # Strategy 4: Normalised partial match - base model in AircraftType name
          if base_model.present?
            base_model_downcase = base_model.downcase
            normalised_match = commercial_variants.find do |at|
              name_downcase = at.name&.downcase || ''
              name_downcase.include?(base_model_downcase)
            end
            return normalised_match if normalised_match
          end

          # Strategy 5: Smart fallback - prefer commercial variants
          find_best_commercial_variant(variants, type_code, base_model)
        end

        # Finds the best commercial variant from a list of AircraftTypes.
        # Strongly deprioritizes executive (BBJ/ACJ) and military variants.
        #
        # Scoring criteria:
        # - Heavily penalise non-commercial variants (BBJ, ACJ, military)
        # - Prefer variants with a manufacturer (indicates canonical entry)
        # - Prefer variants whose name contains the base model designation
        # - Prefer variants whose name contains common series numbers (737-800, A320, etc.)
        #
        # @param variants [Array<AircraftType>] The variants to choose from
        # @param type_code [String] The ICAO type code
        # @param base_model [String, nil] The normalised base model (e.g., "737-800")
        # @return [AircraftType] The best commercial variant
        def find_best_commercial_variant(variants, type_code, base_model)
          type_code_pattern = type_code.downcase.gsub(/[^a-z0-9]/, '')
          base_model_pattern = base_model&.downcase&.gsub(/[^a-z0-9]/, '')

          variants.max_by do |at|
            name = at.name || ''
            name_downcase = name.downcase
            name_normalised = name_downcase.gsub(/[^a-z0-9]/, '')

            score = 0

            # Heavily penalise non-commercial variants
            score -= 500 if non_commercial_variant?(name)

            # Penalise freighter variants (usually not what we want for passenger aircraft)
            score -= 100 if freighter_variant?(name)

            # Prefer variants with a manufacturer
            score += 100 if at.manufacturer_id.present?

            # Prefer variants whose name contains the base model (e.g., "737-800" in name)
            score += 200 if base_model_pattern.present? && name_normalised.include?(base_model_pattern)

            # Prefer variants whose name contains the type code
            score += 50 if name_normalised.include?(type_code_pattern)

            # Prefer names with common commercial patterns (series numbers)
            score += 75 if name_downcase.match?(/\d{3}/) # Contains 3-digit series like 737-800, A320

            # Small bonus for manufacturer prefix (Boeing, Airbus, etc.)
            score += 25 if name_downcase.match?(/\A(boeing|airbus|embraer|bombardier|atr)\b/)

            score
          end
        end

        # Assigns the operator to an aircraft based on source data.
        # Uses pre-loaded cache to avoid N+1 queries.
        #
        # Matching strategy:
        # 1. Try ICAO code lookup (most reliable)
        # 2. Try exact name match (case-insensitive)
        # 3. Try normalised name match (strips "Pty Ltd", "Airlines", etc.)
        # 4. Create new operator if no match found
        #
        # @param record [::Aircraft] The aircraft record
        # @param sources [Array] The source records
        def assign_operator(record, sources)
          # Find the highest-trust source with operator data
          source_with_operator = sources
            .select { |s| s.operator_name.present? || s.operator_icao.present? }
            .max_by { |s| TrustCalculator.new(s, field: :operator_name, entity_type: ENTITY_TYPE).calculate }

          return unless source_with_operator

          # Strategy 1: Try ICAO lookup first (from cache)
          operator = @operators_by_icao[source_with_operator.operator_icao] if source_with_operator.operator_icao.present?

          # Strategy 2: Try exact name match (case-insensitive)
          if operator.nil? && source_with_operator.operator_name.present?
            operator = @operators_by_name[source_with_operator.operator_name.downcase]
          end

          # Strategy 3: Try normalised name match
          # This handles cases like "VIRGIN AUSTRALIA INTERNATIONAL AIRLINES PTY LTD" -> "Virgin Australia"
          if operator.nil? && source_with_operator.operator_name.present?
            source_normalised_key = aggressive_canonical_key(source_with_operator.operator_name)
            operator = @operators_by_normalised_name[source_normalised_key] if source_normalised_key.present?
          end

          # Strategy 4: Create an operator if not found and add to cache
          if operator.nil? && source_with_operator.operator_name.present?
            country = cached_country_for_source(source_with_operator)
            if country
              operator = ::Operator.create!(
                name: source_with_operator.operator_name,
                country: country
              )
              # Add to all caches for subsequent lookups
              @operators_by_name[operator.name.downcase] = operator
              normalised_key = aggressive_canonical_key(operator.name)
              @operators_by_normalised_name[normalised_key] = operator if normalised_key.present?
            end
          end

          record.operator = operator if operator.present?
        end

        # Assigns the registration country to an aircraft based on source data.
        # Uses pre-loaded cache to avoid N+1 queries.
        #
        # Strategy:
        # 1. Look for a source with explicit country code (e.g., from CASA)
        # 2. Fall back to deriving country from registration prefix (e.g., VH- -> Australia)
        #
        # @param record [::Aircraft] The aircraft record
        # @param sources [Array] The source records
        def assign_registration_country(record, sources)
          # Strategy 1: Find a source with explicit country code
          source_with_country = sources.find { |s| s.registration_country_code.present? }
          if source_with_country
            country = @countries_by_iso[source_with_country.registration_country_code]
            record.registration_country = country if country.present?
            return
          end

          # Strategy 2: Derive country from registration prefix
          source_with_registration = sources.find { |s| s.registration.present? }
          return unless source_with_registration

          country_code = RegistrationPrefixLookup.country_code_for(source_with_registration.registration)
          return unless country_code

          country = @countries_by_iso[country_code]
          record.registration_country = country if country.present?
        end

        # Finds the country for a source based on its country code or registration prefix (from cache).
        #
        # @param source [AircraftSource] The source record
        # @return [::Country, nil]
        def cached_country_for_source(source)
          # Try explicit country code first
          if source.registration_country_code.present?
            return @countries_by_iso[source.registration_country_code]
          end

          # Fall back to registration prefix lookup
          return nil unless source.registration.present?

          country_code = RegistrationPrefixLookup.country_code_for(source.registration)
          return nil unless country_code

          @countries_by_iso[country_code]
        end

        # Logs conflict information for later review.
        #
        # @param conflicts [Array<Hash>] The conflicts to log
        def log_conflicts(conflicts)
          Rails.logger.info "Aircraft combine completed with #{conflicts.count} field conflicts"

          # Print formatted conflicts to console
          ConflictFormatter.print_grouped_by_identifier(conflicts)

          # Also log the summary
          Rails.logger.info ConflictFormatter.summary(conflicts)
        end

        # Converts a record to a hash of attributes for batch insert (new records).
        #
        # @param record [::Aircraft] The aircraft record
        # @return [Hash] Attributes hash (without id - let PostgreSQL generate it)
        def record_to_insert_attributes(record)
          now = Time.current
          {
            icao: record.icao,
            registration: record.registration,
            serial_number: record.serial_number,
            model: record.model,
            owner: record.owner,
            engine_count: record.engine_count,
            engine_model: record.engine_model,
            registration_date: record.registration_date,
            aircraft_type_id: record.aircraft_type_id,
            operator_id: record.operator_id,
            registration_country_id: record.registration_country_id,
            manufacture_year: record.manufacture_year,
            cabin_configuration: record.cabin_configuration,
            aircraft_name: record.aircraft_name,
            status: record.status,
            field_provenance: record.field_provenance,
            last_combined_at: record.last_combined_at,
            created_at: now,
            updated_at: now
          }
        end

        # Converts a record to a hash of attributes for batch update (existing records).
        #
        # @param record [::Aircraft] The aircraft record
        # @return [Hash] Attributes hash (with id for upsert matching)
        def record_to_update_attributes(record)
          now = Time.current
          {
            id: record.id,
            icao: record.icao,
            registration: record.registration,
            serial_number: record.serial_number,
            model: record.model,
            owner: record.owner,
            engine_count: record.engine_count,
            engine_model: record.engine_model,
            registration_date: record.registration_date,
            aircraft_type_id: record.aircraft_type_id,
            operator_id: record.operator_id,
            registration_country_id: record.registration_country_id,
            manufacture_year: record.manufacture_year,
            cabin_configuration: record.cabin_configuration,
            aircraft_name: record.aircraft_name,
            status: record.status,
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

          ::Aircraft.insert_all(records)
        end

        # Flushes pending updates to the database in a batch.
        #
        # @param records [Array<Hash>] Array of attribute hashes
        def flush_updates(records)
          return if records.empty?

          ::Aircraft.upsert_all(records, unique_by: :id)
        end
      end
    end
  end
end