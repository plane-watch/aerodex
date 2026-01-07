# frozen_string_literal: true

module Processors
  module Operator
    # Processor for combining operator data from multiple sources.
    #
    # This processor performs a full outer join between VRS and OpenTravel operator
    # data sources, using trust-based field selection to determine the best value
    # for each field when sources disagree.
    class Operator < Processors::Base
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Operator'

      # Patterns for normalising operator names to canonical forms
      OPERATOR_REWRITE_PATTERNS = [
        [/Royal Flying Doctor Service.*/, 'Royal Flying Doctor Service'],
        [/State Of New South Wales Represented By Nsw Police Force/, 'NSW Police Force'],
        [/State Of New South Wales Represented By Nsw Rural Fire Service/, 'NSW Rural Fire Service'],
        [/State Of Western Australia - Represented By Commissioner Of Police/, 'Western Australia Police Force']
      ].freeze

      # The minimum Jaro-Winkler similarity score for fuzzy name matching when ICAO is present
      FUZZY_MATCH_THRESHOLD_WITH_ICAO = 0.75

      # The minimum Jaro-Winkler similarity score for fuzzy name matching when only IATA is present
      FUZZY_MATCH_THRESHOLD_IATA_ONLY = 0.75

      # The fields to merge when combining sources
      MERGE_FIELDS = %i[name icao_code iata_code].freeze

      # Source name for auto-inserted operators (from aircraft imports)
      AUTO_INSERTED_SOURCE = 'AircraftImport'

      class << self
        include OperatorNameCanonicalisation

        # Merges duplicate operators that have the same canonical name key.
        # Only merges "easy" duplicates where ICAO/IATA codes don't conflict.
        #
        # @param dry_run [Boolean] If true, only report what would be merged
        # @return [Hash] Statistics about the merge operation
        #
        # @example
        #   Processors::Operator::Operator.merge_duplicates(dry_run: true)
        #   Processors::Operator::Operator.merge_duplicates
        def merge_duplicates(dry_run: false)
          duplicates = find_duplicate_groups
          stats = { groups: duplicates.count, merged: 0, skipped: 0, errors: [] }

          Rails.logger.info "Found #{duplicates.count} duplicate groups"

          progress_bar = create_progress_bar(duplicates.count)

          duplicates.each do |key, operators|
            result = merge_duplicate_group(operators, dry_run: dry_run)

            case result[:status]
            when :merged
              stats[:merged] += 1
            when :skipped
              stats[:skipped] += 1
            when :error
              stats[:errors] << result[:error]
            end

            progress_bar.increment!
          end

          Rails.logger.info "Merge complete: #{stats[:merged]} merged, #{stats[:skipped]} skipped, #{stats[:errors].count} errors"

          # Reindex after merging
          ::Operator.reindex! unless dry_run

          stats
        end

        # Adds provenance to operators that were auto-inserted from aircraft imports.
        # These operators have no provenance because they weren't created from source tables.
        #
        # @return [Hash] Statistics about the operation
        #
        # @example
        #   Processors::Operator::Operator.add_auto_inserted_provenance
        def add_auto_inserted_provenance
          # Find operators without provenance
          operators = ::Operator.where("field_provenance IS NULL OR field_provenance = ?", "{}")
          total = operators.count

          Rails.logger.info "Adding provenance to #{total} auto-inserted operators"

          progress_bar = create_progress_bar(total)
          updated = 0

          operators.find_each do |operator|
            # Set derived provenance for the name field
            operator.set_derived_provenance(
              :name,
              source_name: AUTO_INSERTED_SOURCE,
              confidence: 30  # Low confidence - not from authoritative source
            )

            # Also set for any other fields that have values
            operator.set_derived_provenance(:icao_code, source_name: AUTO_INSERTED_SOURCE, confidence: 30) if operator.icao_code.present?
            operator.set_derived_provenance(:iata_code, source_name: AUTO_INSERTED_SOURCE, confidence: 30) if operator.iata_code.present?

            operator.last_combined_at ||= Time.current
            operator.save!
            updated += 1
            progress_bar.increment!
          end

          Rails.logger.info "Added provenance to #{updated} operators"

          { total: total, updated: updated }
        end

        # Combines a single operator by ICAO code, IATA code, or name.
        #
        # @param identifier [String] The ICAO code, IATA code, or operator name
        # @param by [Symbol] The identifier type (:icao, :iata, or :name). Default: auto-detect
        # @return [Hash] Result with :operator, :created, :updated, or :error
        #
        # @example By ICAO code
        #   result = Processors::Operator::Operator.combine_one("QFA")
        #   result[:operator]  # => <Operator icao_code: "QFA">
        #
        # @example By name
        #   result = Processors::Operator::Operator.combine_one("Qantas", by: :name)
        def combine_one(identifier, by: nil)
          identifier = identifier.to_s.strip
          raise ArgumentError, "Identifier is required" if identifier.blank?

          # Auto-detect identifier type if not specified
          by ||= case identifier.length
                 when 2 then :iata
                 when 3 then :icao
                 else :name
                 end

          # Gather sources for this operator
          sources = gather_sources_for_identifier(identifier, by)

          if sources.empty?
            return { error: "No sources found for #{by}: #{identifier}" }
          end

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)

          # Find existing operator or create new
          operator = find_existing_operator(identifier, by)
          is_new_record = operator.nil?
          operator ||= ::Operator.new

          # Merge fields using trust-based selection
          conflicts = []
          MERGE_FIELDS.each do |field|
            merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

            operator.public_send("#{field}=", merger.best_value)

            if merger.best_source && merger.best_value.present?
              operator.set_provenance(field, source: merger.best_source, confidence: merger.best_confidence)
            end

            conflicts << merger.conflict_details if merger.has_conflict?
          end

          operator.last_combined_at = Time.current

          unless operator.valid?
            return { error: operator.errors.full_messages, operator: operator }
          end

          operator.save!

          result = { operator: operator, conflicts: conflicts }
          result[:created] = true if is_new_record
          result[:updated] = true unless is_new_record
          result
        end

        # Gathers all sources for a specific operator identifier.
        # Only returns includable records (excludes flagged records).
        #
        # @param identifier [String] The identifier value
        # @param by [Symbol] The identifier type (:icao, :iata, or :name)
        # @return [Array<ApplicationRecord>] All source records matching the identifier
        def gather_sources_for_identifier(identifier, by)
          sources = []

          case by
          when :icao
            sources.concat(Source::Operator::VRSDataOperatorSource.includable.where(icao_code: identifier).to_a)
            sources.concat(Source::Operator::OpenTravelOperatorSource.includable.where(icao_code: identifier).to_a)
            sources.concat(Source::Operator::OpenFlightsOperatorSource.includable.where(icao_code: identifier).to_a) if defined?(Source::Operator::OpenFlightsOperatorSource)
          when :iata
            sources.concat(Source::Operator::VRSDataOperatorSource.includable.where(iata_code: identifier).to_a)
            sources.concat(Source::Operator::OpenTravelOperatorSource.includable.where(iata_code: identifier).to_a)
            sources.concat(Source::Operator::OpenFlightsOperatorSource.includable.where(iata_code: identifier).to_a) if defined?(Source::Operator::OpenFlightsOperatorSource)
          when :name
            # Case-insensitive name search
            sources.concat(Source::Operator::VRSDataOperatorSource.includable.where("LOWER(name) = ?", identifier.downcase).to_a)
            sources.concat(Source::Operator::OpenTravelOperatorSource.includable.where("LOWER(name) = ?", identifier.downcase).to_a)
          end

          sources
        end

        # Finds an existing operator by identifier.
        #
        # @param identifier [String] The identifier value
        # @param by [Symbol] The identifier type
        # @return [::Operator, nil]
        def find_existing_operator(identifier, by)
          case by
          when :icao then ::Operator.find_by(icao_code: identifier)
          when :iata then ::Operator.find_by(iata_code: identifier)
          when :name then ::Operator.find_by("LOWER(name) = ?", identifier.downcase)
          end
        end

        # Combines operator data from all available sources into canonical Operator records.
        #
        # The combination process:
        # 1. Preloads all source data into memory
        # 2. Iterates through all VRS records
        # 3. Attempts to find a matching OpenTravel record
        # 4. Uses FieldMerger to select the best value for each field
        # 5. Creates the canonical Operator with provenance tracking
        # 6. Processes any remaining unmatched OpenTravel records
        #
        # @return [Array<Hash>, true] Returns array of errors if any, otherwise true
        def combine_sources
          preload_reference_data

          errors = []
          conflicts = []

          progress_bar = create_progress_bar(@vrs_records.count)

          with_bulk_import do
            ::Operator.transaction do
              # Phase 1: Process VRS records, matching with OTD where possible
              @vrs_records.each do |vrs_record|
                otd_record = find_matching_otd(vrs_record)

                result = if otd_record.present?
                           @remaining_otd_ids.delete(otd_record.id)
                           merge_sources(vrs_record, otd_record, conflicts)
                         else
                           create_from_single_source(vrs_record)
                         end

                errors << result[:error] if result[:error]
                progress_bar.increment!
              end

              # Phase 2: Process remaining unmatched OTD records
              progress_bar = create_progress_bar(@remaining_otd_ids.count)
              @remaining_otd_ids.each do |otd_id|
                otd_record = @otd_by_id[otd_id]
                result = create_from_single_source(otd_record)
                errors << result[:error] if result[:error]
                progress_bar.increment!
              end
            end
          end

          # Log any conflicts for review
          log_conflicts(conflicts) if conflicts.any?

          # Force Meilisearch reindex
          ::Operator.reindex!

          # Create an import report
          new_import_report(errors, @vrs_records.count + @remaining_otd_ids.count)

          errors.any? ? errors : true
        ensure
          clear_caches
        end

        # Preloads all reference data needed for combining into memory.
        # Only loads includable records (excludes records flagged as invalid).
        def preload_reference_data
          # Preload all VRS records (excluding flagged records)
          @vrs_records = Source::Operator::VRSDataOperatorSource.includable.to_a

          # Preload all OTD records indexed by ID and by codes for fast lookup
          @otd_by_id = Source::Operator::OpenTravelOperatorSource.includable.index_by(&:id)
          @remaining_otd_ids = @otd_by_id.keys.to_set

          # Build lookup indexes for OTD records
          @otd_by_icao = Source::Operator::OpenTravelOperatorSource.includable.where.not(icao_code: nil)
                                                                   .group_by(&:icao_code)
          @otd_by_iata = Source::Operator::OpenTravelOperatorSource.includable.where.not(iata_code: nil)
                                                                   .group_by(&:iata_code)

          # Preload AirlineCodes records indexed by ICAO code for country lookup
          @airlinecodes_by_icao = Source::Operator::AirlineCodesOperatorSource.includable.index_by(&:icao_code)

          # Preload countries by name for fast lookup
          @countries_by_name = ::Country.all.index_by { |c| c.name.downcase }

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)
        end

        # Clears all cached data after processing.
        def clear_caches
          @vrs_records = nil
          @otd_by_id = nil
          @remaining_otd_ids = nil
          @otd_by_icao = nil
          @otd_by_iata = nil
          @airlinecodes_by_icao = nil
          @countries_by_name = nil
        end

        # Normalises an operator name using the rewrite patterns.
        #
        # @param name [String] The name to normalise
        # @return [String] The normalised name
        def normalise_name(name)
          result = name.dup
          OPERATOR_REWRITE_PATTERNS.each { |pattern, replacement| result.gsub!(pattern, replacement) }
          result
        end

        private

        # Finds a matching OpenTravel record for a VRS record.
        #
        # First attempts an exact match on code + name, then falls back to fuzzy
        # matching on name similarity.
        #
        # @param vrs_record [VRSDataOperatorSource] The VRS record to match
        # @return [OpenTravelOperatorSource, nil] The matching record or nil
        def find_matching_otd(vrs_record)
          # Try exact match first
          exact_match = find_exact_otd_match(vrs_record)
          return exact_match if exact_match

          # Fall back to fuzzy matching
          find_fuzzy_otd_match(vrs_record)
        end

        # Attempts to find an exact match on code and name using preloaded data.
        #
        # @param vrs_record [VRSDataOperatorSource]
        # @return [OpenTravelOperatorSource, nil]
        def find_exact_otd_match(vrs_record)
          candidates = if vrs_record.icao_code.present?
                         @otd_by_icao[vrs_record.icao_code] || []
                       else
                         @otd_by_iata[vrs_record.iata_code] || []
                       end

          candidates.find { |c| c.name == vrs_record.name }
        end

        # Performs fuzzy matching to find an OTD record using preloaded data.
        #
        # @param vrs_record [VRSDataOperatorSource]
        # @return [OpenTravelOperatorSource, nil]
        def find_fuzzy_otd_match(vrs_record)
          threshold = vrs_record.icao_code.present? ? FUZZY_MATCH_THRESHOLD_WITH_ICAO : FUZZY_MATCH_THRESHOLD_IATA_ONLY
          best_match = { record: nil, confidence: 0 }

          # Build candidates from preloaded data
          candidates = []
          candidates.concat(@otd_by_icao[vrs_record.icao_code] || []) if vrs_record.icao_code.present?
          candidates.concat(@otd_by_iata[vrs_record.iata_code] || []) if vrs_record.iata_code.present?
          candidates.uniq!

          # Filter out candidates with conflicting ICAO codes. ICAO codes are
          # authoritative unique identifiers - if the VRS record has an ICAO code,
          # we should only consider OTD candidates with matching (or absent) ICAO codes.
          if vrs_record.icao_code.present?
            candidates.reject! do |c|
              c.icao_code.present? && c.icao_code != vrs_record.icao_code
            end
          end

          candidates.each do |candidate|
            confidence = calculate_match_confidence(vrs_record, candidate)

            if confidence >= threshold && confidence > best_match[:confidence]
              best_match = { record: candidate, confidence: confidence }
            end
          end

          best_match[:record]
        end

        # Calculates the match confidence between a VRS and OTD record.
        #
        # @param vrs_record [VRSDataOperatorSource]
        # @param otd_record [OpenTravelOperatorSource]
        # @return [Float] The confidence score (0.0 to 1.0)
        def calculate_match_confidence(vrs_record, otd_record)
          # Perfect match if both codes match
          if vrs_record.icao_code == otd_record.icao_code &&
             vrs_record.iata_code == otd_record.iata_code
            return 1.0
          end

          # Reject if ICAO codes conflict (both present but different).
          # ICAO codes are authoritative unique identifiers - different ICAO codes
          # mean different operators, even if they share an IATA code.
          if vrs_record.icao_code.present? &&
             otd_record.icao_code.present? &&
             vrs_record.icao_code != otd_record.icao_code
            return 0.0
          end

          # Cannot calculate similarity without a name
          return 0.0 if vrs_record.name.blank?

          # Otherwise, use name similarity
          all_names = [otd_record.name].compact
          all_names += otd_record.data['alt_names'] if otd_record.data['alt_names'].present?
          all_names.compact!

          return 0.0 if all_names.empty?

          all_names.map { |name| JaroWinkler.similarity(vrs_record.name, name) }.max || 0.0
        end

        # Merges two source records into a canonical Operator using trust-based selection.
        # Finds and updates existing operators rather than creating duplicates.
        #
        # @param vrs_record [VRSDataOperatorSource]
        # @param otd_record [OpenTravelOperatorSource]
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :operator or :error key
        def merge_sources(vrs_record, otd_record, conflicts)
          sources = [vrs_record, otd_record]

          # Find existing operator by ICAO, IATA, or name (in that order of preference)
          operator = find_existing_operator_from_sources(sources)
          is_new = operator.nil?
          operator ||= ::Operator.new

          MERGE_FIELDS.each do |field|
            merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

            operator.public_send("#{field}=", merger.best_value)

            # Track provenance for this field
            if merger.best_source && merger.best_value.present?
              operator.set_provenance(field, source: merger.best_source, confidence: merger.best_confidence)
            end

            # Collect conflict information for logging
            conflicts << merger.conflict_details if merger.has_conflict?
          end

          # Resolve country from AirlineCodes if not already set
          if operator.country_id.blank?
            icao = operator.icao_code || vrs_record.icao_code || otd_record.icao_code
            country = resolve_country_for_operator(icao)
            operator.country = country if country
          end

          operator.last_combined_at = Time.current

          if operator.valid?
            operator.save!
            { operator: operator, created: is_new, updated: !is_new }
          else
            {
              error: {
                record: operator.attributes,
                source: 'Merged',
                vrs_id: vrs_record.id,
                otd_id: otd_record.id,
                errors: operator.errors.full_messages
              }
            }
          end
        end

        # Creates or updates an Operator from a single source record.
        # Finds existing operators rather than creating duplicates.
        #
        # @param source_record [ApplicationRecord] The source record
        # @return [Hash] Result with :operator or :error key
        def create_from_single_source(source_record)
          # Find existing operator by ICAO, IATA, or name
          operator = find_existing_operator_from_sources([source_record])
          is_new = operator.nil?

          if is_new
            operator = ::Operator.new(
              name: source_record.name,
              icao_code: source_record.icao_code,
              iata_code: source_record.iata_code
            )
          else
            # Update fields if source has better data
            operator.name = source_record.name if source_record.name.present?
            operator.icao_code = source_record.icao_code if source_record.icao_code.present? && operator.icao_code.blank?
            operator.iata_code = source_record.iata_code if source_record.iata_code.present? && operator.iata_code.blank?
          end

          # Set provenance for all fields from this source
          confidence = TrustCalculator.new(
            source_record,
            field: :name,
            entity_type: ENTITY_TYPE
          ).calculate

          MERGE_FIELDS.each do |field|
            value = source_record.public_send(field)
            next unless value.present?

            operator.set_provenance(field, source: source_record, confidence: confidence)
          end

          # Resolve country from AirlineCodes if not already set
          if operator.country_id.blank?
            icao = operator.icao_code || source_record.icao_code
            country = resolve_country_for_operator(icao)
            operator.country = country if country
          end

          operator.last_combined_at = Time.current

          if operator.valid?
            operator.save!
            { operator: operator, created: is_new, updated: !is_new }
          else
            {
              error: {
                record: source_record.attributes,
                source: source_record.class.name.demodulize,
                errors: operator.errors.full_messages
              }
            }
          end
        end

        # Finds an existing operator that matches any of the source records.
        # Searches by ICAO code first, then falls back to name match.
        # Does NOT search by IATA code as IATA codes can be shared across operators.
        #
        # @param sources [Array<ApplicationRecord>] The source records to search for
        # @return [::Operator, nil] The matching operator or nil
        def find_existing_operator_from_sources(sources)
          # Check if any source has an ICAO code - this affects our search strategy.
          # ICAO codes are authoritative unique identifiers. If a source has an ICAO code,
          # we should ONLY match operators with that same ICAO code, not fall through
          # to IATA/name matching which could find a different operator.
          icao_codes = sources.map(&:icao_code).compact.uniq
          has_icao = icao_codes.any?

          # Try ICAO codes first (most reliable)
          if has_icao
            operator = ::Operator.find_by(icao_code: icao_codes)
            return operator if operator

            # Source has ICAO but no match found - do NOT fall through to IATA/name search.
            # This would risk matching/updating a different operator that shares IATA code.
            return nil
          end

          # Note: We intentionally do NOT search by IATA code. IATA codes can be
          # legitimately shared across different operators (e.g., airline groups),
          # so matching by IATA would risk finding the wrong operator.

          # Fall back to exact name match (case-insensitive) - only if no ICAO code
          names = sources.map(&:name).compact.uniq
          names.each do |name|
            operator = ::Operator.find_by("LOWER(name) = ?", name.downcase)
            return operator if operator
          end

          nil
        end

        # Logs conflict information for later review.
        #
        # @param conflicts [Array<Hash>] The conflicts to log
        def log_conflicts(conflicts)
          Rails.logger.info "Operator combine completed with #{conflicts.count} field conflicts"
          conflicts.each do |conflict|
            Rails.logger.debug "Conflict on #{conflict[:field]}: " \
                               "#{conflict[:candidates].map { |c| "#{c[:source_type]}=#{c[:value].inspect}" }.join(' vs ')}"
          end
        end

        # Resolves the country for an operator from AirlineCodes data.
        # Uses the ICAO code to look up country information.
        #
        # @param icao_code [String, nil] The ICAO code to look up
        # @return [Country, nil] The resolved Country record or nil
        def resolve_country_for_operator(icao_code)
          return nil if icao_code.blank?
          return nil unless @airlinecodes_by_icao

          airlinecodes_source = @airlinecodes_by_icao[icao_code]
          return nil unless airlinecodes_source

          country_name = airlinecodes_source.data['country']
          return nil if country_name.blank?

          # Try exact match first
          country = @countries_by_name[country_name.downcase]
          return country if country

          # Try common country name variations
          normalised = normalise_country_name(country_name)
          @countries_by_name[normalised.downcase]
        end

        # Normalises country names to match our database.
        # Handles common variations from external sources.
        #
        # @param name [String] The country name to normalise
        # @return [String] The normalised name
        def normalise_country_name(name)
          case name
          when 'US', 'USA', 'United States of America'
            'United States'
          when 'UK'
            'United Kingdom'
          when 'UAE'
            'United Arab Emirates'
          when 'South Korea', 'Korea, South'
            'Republic of Korea'
          when 'North Korea', 'Korea, North'
            "Democratic People's Republic of Korea"
          when 'Czech Republic'
            'Czechia'
          when 'Russia'
            'Russian Federation'
          when 'Taiwan'
            'Taiwan, Province of China'
          when 'Vietnam'
            'Viet Nam'
          when 'Iran'
            'Iran, Islamic Republic of'
          when 'Syria'
            'Syrian Arab Republic'
          when /Cote D'?[Ii]voire/
            "Côte d'Ivoire"
          else
            name
          end
        end

        # Finds groups of operators that have the same canonical name key.
        # Groups by canonical_name_key + country_id to avoid false positives.
        #
        # @return [Hash<String, Array<Operator>>] Groups keyed by canonical key
        def find_duplicate_groups
          operators = ::Operator.all.to_a

          # Group by canonical key + country
          groups = {}
          operators.each do |op|
            key = "#{canonical_name_key(op.name)}_#{op.country_id}"
            groups[key] ||= []
            groups[key] << op
          end

          # Return only groups with duplicates
          groups.select { |_k, v| v.size > 1 }
        end

        # Merges a group of duplicate operators into one.
        # Picks the best operator to keep and reassigns all aircraft to it.
        #
        # @param operators [Array<Operator>] The duplicate operators
        # @param dry_run [Boolean] If true, only report what would happen
        # @return [Hash] Result with :status key (:merged, :skipped, or :error)
        def merge_duplicate_group(operators, dry_run: false)
          # Check if this group has conflicting ICAO/IATA codes
          icao_codes = operators.map(&:icao_code).compact.uniq
          iata_codes = operators.map(&:iata_code).compact.uniq

          if icao_codes.size > 1 || iata_codes.size > 1
            # Different codes - these might be genuinely different operators
            return { status: :skipped, reason: 'Conflicting codes', codes: { icao: icao_codes, iata: iata_codes } }
          end

          # Build candidates for best_name_from
          candidates = operators.map do |op|
            {
              operator: op,
              name: op.name,
              has_icao: op.icao_code.present?,
              has_iata: op.iata_code.present?
            }
          end

          # Pick the best operator to keep
          best_candidate = candidates.max_by do |c|
            name_quality_score(c[:name], has_icao: c[:has_icao], has_iata: c[:has_iata])
          end

          survivor = best_candidate[:operator]
          duplicates = operators - [survivor]

          if dry_run
            Rails.logger.info "Would merge: #{duplicates.map(&:name).inspect} -> #{survivor.name}"
            return { status: :merged, survivor: survivor.name, merged: duplicates.map(&:name) }
          end

          # Merge duplicates into survivor
          ::Operator.transaction do
            duplicates.each do |duplicate|
              # Reassign aircraft to survivor
              duplicate.aircraft.update_all(operator_id: survivor.id)

              # Merge any codes the survivor is missing
              survivor.icao_code ||= duplicate.icao_code
              survivor.iata_code ||= duplicate.iata_code

              # Delete the duplicate
              duplicate.destroy!
            end

            # Update survivor's name if we picked a better one
            survivor.name = best_name_from(candidates) || survivor.name
            survivor.save!
          end

          { status: :merged, survivor: survivor.name, merged_count: duplicates.size }
        rescue StandardError => e
          { status: :error, error: e.message, operators: operators.map(&:name) }
        end
      end
    end
  end
end