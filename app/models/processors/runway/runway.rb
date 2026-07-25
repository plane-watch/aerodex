# frozen_string_literal: true

module Processors
  module Runway
    # Processor for combining runway data from sources into canonical AirportRunway records.
    #
    # Runways are matched by airport (via ICAO code lookup) and runway identifier.
    # Currently only supports OurAirports as a source.
    class Runway < Processors::Base
      # The entity type for trust score lookups
      ENTITY_TYPE = 'Runway'

      # The fields to merge when combining sources
      MERGE_FIELDS = %i[length width surface lighted closed].freeze

      class << self
        # Combines a single runway by airport ICAO code and runway identifier.
        #
        # @param airport_icao [String] The airport ICAO code (e.g., "YSSY")
        # @param le_ident [String, nil] The low-end runway identifier (e.g., "16L"). If nil, combines all runways.
        # @return [Hash] Result with :runway(s), :created, :updated, or :error
        #
        # @example Combine a specific runway
        #   result = Processors::Runway::Runway.combine_one("YSSY", "16L")
        #   result[:runway]  # => <AirportRunway le_ident: "16L">
        #
        # @example Combine all runways at an airport
        #   result = Processors::Runway::Runway.combine_one("YSSY")
        #   result[:runways]  # => [<AirportRunway>, ...]
        def combine_one(airport_icao, le_ident = nil)
          airport_icao = airport_icao.to_s.strip.upcase
          raise ArgumentError, 'Airport ICAO code is required' if airport_icao.blank?

          # Preload reference data
          preload_reference_data

          # Find the canonical airport
          airport = @airports_by_icao[airport_icao]
          unless airport
            return { error: "Airport not found: #{airport_icao}" }
          end

          # Gather sources for this airport's runways
          sources = if le_ident.present?
                      Source::Runway::OurAirportsRunwaySource.includable.where(airport_ident: airport_icao, le_ident: le_ident).to_a
                    else
                      Source::Runway::OurAirportsRunwaySource.includable.where(airport_ident: airport_icao).to_a
                    end

          if sources.empty?
            return { error: "No runway sources found for airport: #{airport_icao}#{le_ident ? " / #{le_ident}" : ''}" }
          end

          results = []
          sources.each do |source|
            result = merge_runway(airport, source)
            if result[:error]
              results << { error: result[:error] }
            else
              runway = result[:runway]
              results << {
                runway: runway,
                created: runway.id_previously_changed?,
                updated: !runway.id_previously_changed?
              }
            end
          end

          if le_ident.present?
            results.first
          else
            { runways: results }
          end
        ensure
          clear_caches
        end

        # Combines runway data from all sources into staged changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @return [StagedBatch] The batch containing staged changes
        def combine_sources(triggered_by: nil)
          with_staged_batch(entity_type: 'Runway', triggered_by: triggered_by) do
            preload_reference_data

            # Group runway sources by airport (only includable/non-excluded sources)
            runway_sources = Source::Runway::OurAirportsRunwaySource.includable.group_by(&:airport_ident)

            progress_bar = create_progress_bar(runway_sources.count)

            runway_sources.each do |airport_ident, runways|
              # Find the canonical airport from preloaded cache
              airport = @airports_by_icao[airport_ident]

              unless airport
                # Skip runways for airports we don't have
                progress_bar.increment!
                next
              end

              runways.each do |source|
                merge_runway_staged(airport, source)
              end

              progress_bar.increment!
            end
          end
        ensure
          clear_caches
        end

        # Preloads all reference data needed for combining into memory.
        def preload_reference_data
          @airports_by_icao = ::Airport.where.not(icao_code: nil).index_by(&:icao_code)

          # Preload existing runways grouped by airport_id and le_ident
          @runways_cache = {}
          AirportRunway.find_each do |runway|
            key = "#{runway.airport_id}:#{runway.le_ident}"
            @runways_cache[key] = runway
          end

          # Ensure trust scores are cached
          SourceTrustScore.send(:ensure_cache_loaded)
        end

        # Clears all cached data after processing.
        def clear_caches
          @airports_by_icao = nil
          @runways_cache = nil
        end

        private

        # Merges a runway source into a staged change.
        #
        # @param airport [Airport] The canonical airport
        # @param source [RunwaySource] The source runway record
        def merge_runway_staged(airport, source)
          # Find or create runway using preloaded cache
          cache_key = "#{airport.id}:#{source.le_ident}"
          record = @runways_cache[cache_key]

          if record.nil?
            record = AirportRunway.new(airport_id: airport.id, le_ident: source.le_ident)
            @runways_cache[cache_key] = record
          end

          is_new_record = record.new_record?

          # Set basic attributes (normalise surface to canonical type)
          record.assign_attributes(
            he_ident: source.he_ident,
            runway_name: source.display_name,
            heading: source.le_heading_deg,
            length: source.length_metres,
            width: source.width_metres,
            surface: RunwaySurfaceNormaliser.normalise(source.surface).to_s,
            lighted: source.lighted,
            closed: source.closed
          )

          # Check for meaningful changes (content fields, not just metadata like provenance)
          meaningful_changes = record.changes.keys - %w[field_provenance last_combined_at]

          # Human-readable identifier for the diff UI
          human_identifier = "#{airport.icao_code}/#{source.le_ident}"

          if is_new_record
            # Set provenance for new records
            MERGE_FIELDS.each do |field|
              if source.public_send(source_field_for(field)).present?
                record.set_provenance(field, source: source, confidence: 85)
              end
            end
            record.last_combined_at = Time.current
            stage_change(record, operation: :create, identifier: human_identifier)
          elsif meaningful_changes.any?
            # Set provenance for updated records
            MERGE_FIELDS.each do |field|
              if source.public_send(source_field_for(field)).present?
                record.set_provenance(field, source: source, confidence: 85)
              end
            end
            record.last_combined_at = Time.current
            stage_change(record, operation: :update, identifier: human_identifier)
          else
            current_batch.summary['unchanged'] += 1
          end
        end

        # Merges a runway source into a canonical AirportRunway record.
        # Used by combine_one for direct saves.
        #
        # @param airport [Airport] The canonical airport
        # @param source [RunwaySource] The source runway record
        # @return [Hash] Result with :runway or :error key
        def merge_runway(airport, source)
          # Find or create runway using preloaded cache
          cache_key = "#{airport.id}:#{source.le_ident}"
          record = @runways_cache[cache_key]

          if record.nil?
            record = AirportRunway.new(airport_id: airport.id, le_ident: source.le_ident)
            @runways_cache[cache_key] = record
          end

          is_new_record = record.new_record?

          # Set basic attributes (normalise surface to canonical type)
          record.assign_attributes(
            he_ident: source.he_ident,
            runway_name: source.display_name,
            heading: source.le_heading_deg,
            length: source.length_metres,
            width: source.width_metres,
            surface: RunwaySurfaceNormaliser.normalise(source.surface).to_s,
            lighted: source.lighted,
            closed: source.closed
          )

          # Check for changes BEFORE setting provenance
          has_changes = is_new_record || record.changes.any?

          if has_changes
            # Only set provenance and save if there are actual changes
            MERGE_FIELDS.each do |field|
              if source.public_send(source_field_for(field)).present?
                record.set_provenance(field, source: source, confidence: 85)
              end
            end

            record.last_combined_at = Time.current
            record.save!(validate: false)
          else
            record.restore_attributes
          end

          { runway: record }
        rescue ActiveRecord::RecordInvalid => e
          {
            error: {
              airport: airport.icao_code,
              runway: source.le_ident,
              errors: e.record.errors.full_messages
            }
          }
        end

        # Maps canonical field names to source field names
        def source_field_for(field)
          case field
          when :length then :length_ft
          when :width then :width_ft
          else field
          end
        end
      end
    end
  end
end