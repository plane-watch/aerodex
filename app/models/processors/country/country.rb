# frozen_string_literal: true

module Processors
  module Country
    # Processor for combining country data from sources into canonical Country records.
    #
    # Uses FieldMerger for consistent source handling, even with a single source currently.
    # This makes adding additional sources straightforward in the future.
    class Country < Processors::Base
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Country'

      # The fields to merge when combining sources
      MERGE_FIELDS = %i[iso_2char_code iso_3char_code iso_num_code name capital].freeze

      class << self
        # Combines a single country by ISO 2-character code.
        #
        # @param iso_code [String] The ISO 2-character country code (e.g., "AU")
        # @return [Hash] Result with :country, :created, :updated, or :error
        #
        # @example
        #   result = Processors::Country::Country.combine_one("AU")
        #   result[:country]  # => <Country iso_2char_code: "AU">
        def combine_one(iso_code)
          iso_code = iso_code.to_s.strip.upcase
          raise ArgumentError, 'ISO 2-character code is required' if iso_code.blank?
          raise ArgumentError, 'ISO code must be 2 characters' if iso_code.length != 2

          # Gather sources for this country
          sources = gather_sources_for_iso_code(iso_code)

          return { error: "No sources found for ISO code: #{iso_code}" } if sources.empty?

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)

          conflicts = []
          result = merge_sources_for_iso(iso_code, sources, conflicts)

          return { error: result[:error] } if result[:error]

          is_new = result[:country]&.id_previously_changed?
          {
            country: result[:country],
            created: is_new,
            updated: !is_new,
            conflicts: conflicts
          }
        end

        # Gathers all sources for a specific country ISO code.
        #
        # @param iso_code [String] The ISO 2-character code
        # @return [Array<ApplicationRecord>] All source records matching the code
        def gather_sources_for_iso_code(iso_code)
          sources = []
          sources.concat(Source::Country::OpenTravelCountrySource.includable.where(iso_2char_code: iso_code).to_a)
          sources.concat(Source::Country::OpenFlightsCountrySource.includable.where(iso_2char_code: iso_code).to_a)
          sources.concat(Source::Country::OurAirportsCountrySource.includable.where(iso_2char_code: iso_code).to_a)
          sources
        end

        # Combines country data from all available sources into staged changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @return [StagedBatch] The batch containing staged changes
        def combine_sources(triggered_by: nil)
          with_staged_batch(entity_type: 'Country', triggered_by: triggered_by) do
            sources_by_iso = group_sources_by_iso
            conflicts = []

            # Ensure trust scores are cached
            SourceTrustScore.send(:ensure_cache_loaded)

            progress_bar = create_progress_bar(sources_by_iso.count)

            sources_by_iso.each do |iso_code, sources|
              record = ::Country.find_or_initialize_by(iso_2char_code: iso_code)

              # Merge each field using FieldMerger
              MERGE_FIELDS.each do |field|
                merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

                record.public_send("#{field}=", merger.best_value)

                # Track provenance for this field
                if merger.best_source && merger.best_value.present?
                  record.set_provenance(field, source: merger.best_source, confidence: merger.best_confidence)
                end

                # Collect conflict information for logging
                conflicts << merger.conflict_details if merger.has_conflict?
              end

              # Stage the change instead of saving
              # Check for meaningful changes (content fields, not just metadata like provenance)
              meaningful_changes = record.changes.keys - %w[field_provenance last_combined_at]

              if record.new_record?
                record.last_combined_at = Time.current
                stage_change(record, operation: :create, identifier: iso_code)
              elsif meaningful_changes.any?
                record.last_combined_at = Time.current
                stage_change(record, operation: :update, identifier: iso_code)
              else
                current_batch.summary['unchanged'] += 1
              end

              progress_bar.increment!
            end

            # Log any conflicts for review
            log_conflicts(conflicts) if conflicts.any?

            # Store conflict count in batch notes if any
            current_batch.notes = "Processing completed with #{conflicts.count} field conflicts" if conflicts.any?
          end
        end

        private

        # Groups all source records by their iso_2char_code.
        #
        # @return [Hash<String, Array>] Sources grouped by iso_2char_code
        def group_sources_by_iso
          sources = {}

          # Add OpenTravel sources
          Source::Country::OpenTravelCountrySource.includable.find_each do |source|
            key = source.iso_2char_code
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          # Add OpenFlights sources
          Source::Country::OpenFlightsCountrySource.includable.find_each do |source|
            key = source.iso_2char_code
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          # Add OurAirports sources
          Source::Country::OurAirportsCountrySource.includable.find_each do |source|
            key = source.iso_2char_code
            next if key.blank?

            sources[key] ||= []
            sources[key] << source
          end

          sources
        end

        # Merges sources for a single iso_2char_code into a canonical Country.
        #
        # @param iso_code [String] The ISO 2-character country code
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :country or :error key
        def merge_sources_for_iso(iso_code, sources, conflicts)
          record = ::Country.find_or_initialize_by(iso_2char_code: iso_code)

          # Merge each field using FieldMerger
          MERGE_FIELDS.each do |field|
            merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

            record.public_send("#{field}=", merger.best_value)

            # Track provenance for this field
            if merger.best_source && merger.best_value.present?
              record.set_provenance(field, source: merger.best_source, confidence: merger.best_confidence)
            end

            # Collect conflict information for logging
            conflicts << merger.conflict_details if merger.has_conflict?
          end

          record.last_combined_at = Time.current

          if record.valid?
            record.save!
            { country: record }
          else
            {
              error: {
                iso_2char_code: iso_code,
                source_count: sources.count,
                errors: record.errors.full_messages
              }
            }
          end
        end

        # Logs conflict information for later review.
        #
        # @param conflicts [Array<Hash>] The conflicts to log
        def log_conflicts(conflicts)
          Rails.logger.info "Country combine completed with #{conflicts.count} field conflicts"
          conflicts.each do |conflict|
            Rails.logger.debug "Conflict on #{conflict[:field]}: " \
                               "#{conflict[:candidates].map do |c|
                                 "#{c[:source_type]}=#{c[:value].inspect}"
                               end.join(' vs ')}"
          end
        end
      end
    end
  end
end
