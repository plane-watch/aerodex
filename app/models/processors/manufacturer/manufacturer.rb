# frozen_string_literal: true

module Processors
  module Manufacturer
    # Processor for combining manufacturer data from sources into canonical Manufacturer records.
    #
    # Uses FieldMerger for consistent source handling, even with a single source currently.
    # This makes adding additional sources straightforward in the future.
    class Manufacturer < Processors::Base
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Manufacturer'

      # The fields to merge when combining sources
      MERGE_FIELDS = %i[icao_code name alt_names].freeze

      class << self
        # Combines a single manufacturer by ICAO code.
        #
        # @param icao_code [String] The manufacturer ICAO code (e.g., "BOEING")
        # @return [Hash] Result with :manufacturer, :created, :updated, or :error
        #
        # @example
        #   result = Processors::Manufacturer::Manufacturer.combine_one("BOEING")
        #   result[:manufacturer]  # => <Manufacturer icao_code: "BOEING">
        def combine_one(icao_code)
          icao_code = icao_code.to_s.strip.upcase
          raise ArgumentError, 'ICAO code is required' if icao_code.blank?

          # Gather sources for this manufacturer
          sources = gather_sources_for_icao_code(icao_code)

          if sources.empty?
            return { error: "No sources found for ICAO code: #{icao_code}" }
          end

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)

          conflicts = []
          result = merge_sources_for_icao(icao_code, sources, conflicts)

          if result[:error]
            return { error: result[:error] }
          end

          is_new = result[:manufacturer]&.id_previously_changed?
          {
            manufacturer: result[:manufacturer],
            created: is_new,
            updated: !is_new,
            conflicts: conflicts
          }
        end

        # Gathers all sources for a specific manufacturer ICAO code.
        #
        # @param icao_code [String] The manufacturer ICAO code
        # @return [Array<ApplicationRecord>] All source records matching the code
        def gather_sources_for_icao_code(icao_code)
          sources = []
          sources.concat(Source::Manufacturer::CfappsICAOIntManufacturerSource.includable.where(icao_code: icao_code).to_a)
          if defined?(Source::Manufacturer::OpenskyManufacturerSource)
            sources.concat(Source::Manufacturer::OpenskyManufacturerSource.includable.where(icao_code: icao_code).to_a)
          end
          sources
        end

        # Combines manufacturer data from all available sources into staged changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @return [StagedBatch] The batch containing staged changes
        def combine_sources(triggered_by: nil)
          with_staged_batch(entity_type: 'Manufacturer', triggered_by: triggered_by) do
            sources_by_icao = group_sources_by_icao
            conflicts = []

            # Ensure trust scores are cached
            SourceTrustScore.send(:ensure_cache_loaded)

            progress_bar = create_progress_bar(sources_by_icao.count)

            sources_by_icao.each do |icao_code, sources|
              record = ::Manufacturer.find_or_initialize_by(icao_code: icao_code)

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

              # Handle country lookup separately (not a simple field merge)
              assign_country(record, sources)

              # Stage the change instead of saving
              # Check for meaningful changes (content fields, not just metadata like provenance)
              meaningful_changes = record.changes.keys - %w[field_provenance last_combined_at]

              if record.new_record?
                record.last_combined_at = Time.current
                stage_change(record, operation: :create, identifier: icao_code)
              elsif meaningful_changes.any?
                record.last_combined_at = Time.current
                stage_change(record, operation: :update, identifier: icao_code)
              else
                current_batch.summary['unchanged'] += 1
              end

              progress_bar.increment!
            end

            # Log any conflicts for review
            log_conflicts(conflicts) if conflicts.any?

            # Store conflict count in batch notes if any
            if conflicts.any?
              current_batch.notes = "Processing completed with #{conflicts.count} field conflicts"
            end
          end
        end

        private

        # Groups all source records by their icao_code.
        #
        # @return [Hash<String, Array>] Sources grouped by icao_code
        def group_sources_by_icao
          sources = {}

          # Add CfappsICAOInt sources
          Source::Manufacturer::CfappsICAOIntManufacturerSource.includable.find_each do |source|
            key = source.icao_code
            sources[key] ||= []
            sources[key] << source
          end

          # Add OpenSky sources
          if defined?(Source::Manufacturer::OpenskyManufacturerSource)
            Source::Manufacturer::OpenskyManufacturerSource.includable.find_each do |source|
              key = source.icao_code
              next if key.blank?

              sources[key] ||= []
              sources[key] << source
            end
          end

          sources
        end

        # Merges sources for a single icao_code into a canonical Manufacturer.
        #
        # @param icao_code [String] The manufacturer ICAO code
        # @param sources [Array] The source records to merge
        # @param conflicts [Array] Array to collect conflict information
        # @return [Hash] Result with :manufacturer or :error key
        def merge_sources_for_icao(icao_code, sources, conflicts)
          record = ::Manufacturer.find_or_initialize_by(icao_code: icao_code)

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

          # Handle country lookup separately (not a simple field merge)
          assign_country(record, sources)

          record.last_combined_at = Time.current

          if record.valid?
            record.save!
            { manufacturer: record }
          else
            {
              error: {
                icao_code: icao_code,
                source_count: sources.count,
                errors: record.errors.full_messages
              }
            }
          end
        end

        # Assigns the country to a manufacturer based on source data.
        # Uses the highest-trust source's country value.
        #
        # @param record [::Manufacturer] The manufacturer record
        # @param sources [Array] The source records
        def assign_country(record, sources)
          # Find the source with country data
          source_with_country = sources.find { |s| s.respond_to?(:country) && s.country.present? }
          return unless source_with_country

          country_name = source_with_country.country
          return if country_name.blank?

          # Try exact match first
          country = ::Country.find_by(name: country_name)

          # If no exact match, try case-insensitive match
          country ||= ::Country.where('LOWER(name) = ?', country_name.downcase).first

          # If still no match, try partial match
          country ||= ::Country.where('LOWER(name) LIKE ?', "%#{country_name.downcase}%").first

          record.country = country if country.present?
        end

        # Logs conflict information for later review.
        #
        # @param conflicts [Array<Hash>] The conflicts to log
        def log_conflicts(conflicts)
          Rails.logger.info "Manufacturer combine completed with #{conflicts.count} field conflicts"
          conflicts.each do |conflict|
            Rails.logger.debug "Conflict on #{conflict[:field]}: " \
                               "#{conflict[:candidates].map { |c| "#{c[:source_type]}=#{c[:value].inspect}" }.join(' vs ')}"
          end
        end
      end
    end
  end
end