# frozen_string_literal: true

module Processors
  module Route
    # Combines VRS route source records into canonical Route and RouteSegment
    # records.
    #
    # For each source row this processor resolves the airline code to an existing
    # Operator and each airport code to an existing Airport. It does NOT create
    # operators or airports; routes whose references cannot be resolved are skipped
    # and reported, then retried on the next run once the data catches up.
    #
    # Each route is staged as a single StagedChange carrying its RouteSegment
    # children as nested attributes, so the existing staged-batch apply path
    # writes the route and its segments atomically.
    #
    # @example Combine every airline's routes
    #   Processors::Route::Route.combine_sources
    #
    # @example Combine one airline (keeps the staged batch reviewable)
    #   Processors::Route::Route.combine_sources(airline_code: 'QFA')
    class Route < Processors::Base
      # The entity type recorded on the staged batch.
      ENTITY_TYPE = 'Route'

      # The model class staged changes target (the canonical, top-level Route).
      RECORD_TYPE = 'Route'

      class << self
        # Combines route sources into staged Route changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @param airline_code [String, nil] Optional airline code to scope the run
        # @return [StagedBatch] The batch containing the staged changes
        def combine_sources(triggered_by: nil, airline_code: nil)
          with_staged_batch(entity_type: ENTITY_TYPE, triggered_by: triggered_by) do
            preload_reference_data

            scope = Source::Route::VRSRouteSource.includable
            scope = scope.where(airline_code: airline_code) if airline_code.present?

            errors = []
            progress_bar = create_progress_bar(scope.count)

            scope.find_each do |source|
              error = combine_one(source)
              errors << error if error
              progress_bar.increment!
            end

            current_batch.notes = "Skipped #{errors.count} routes (unresolved references)" if errors.any?
            record_errors(errors)
          end
        ensure
          clear_caches
        end

        private

        # Preloads operators, airports and existing routes into memory for fast lookup.
        def preload_reference_data
          @operators_by_icao = ::Operator.where.not(icao_code: nil).index_by(&:icao_code)
          @operators_by_iata = ::Operator.where.not(iata_code: nil).index_by(&:iata_code)
          @airports_by_icao = ::Airport.where.not(icao_code: nil).index_by(&:icao_code)
          @airports_by_iata = ::Airport.where.not(iata_code: nil).index_by(&:iata_code)
          @existing_routes = ::Route.includes(:route_segments).index_by { |r| [r.operator_id, r.call_sign] }
        end

        # Clears the preloaded caches after the run.
        def clear_caches
          @operators_by_icao = @operators_by_iata = nil
          @airports_by_icao = @airports_by_iata = nil
          @existing_routes = nil
        end

        # Resolves and stages a single source row.
        #
        # @param source [Source::Route::VRSRouteSource] The source row
        # @return [Hash, nil] An error hash if the route was skipped, otherwise nil
        def combine_one(source)
          operator = resolve_operator(source.airline_code)
          return skip(source, "operator not found: #{source.airline_code}") if operator.nil?

          airports = resolve_airports(source.airport_code_list)
          return skip(source, "unresolved airport in: #{source.airport_codes}") if airports.nil?

          desired_airport_ids = airports.map(&:id)
          existing = @existing_routes[[operator.id, source.callsign]]

          if existing.nil?
            stage_create(operator, source.callsign, desired_airport_ids)
          elsif segments_match?(existing, desired_airport_ids)
            current_batch.summary['unchanged'] += 1
          else
            stage_update(existing, desired_airport_ids)
          end

          nil
        end

        # Resolves an airline code to an Operator (ICAO first, then IATA).
        #
        # @param code [String] The airline code
        # @return [Operator, nil]
        def resolve_operator(code)
          @operators_by_icao[code] || @operators_by_iata[code]
        end

        # Resolves an ordered list of airport codes to Airport records.
        #
        # @param codes [Array<String>] The airport codes in flight order
        # @return [Array<Airport>, nil] The airports in order, or nil if any is unresolved
        def resolve_airports(codes)
          resolved = codes.map { |code| @airports_by_icao[code] || @airports_by_iata[code] }
          return nil if resolved.any?(&:nil?)

          resolved
        end

        # Checks whether an existing route's ordered segments match the desired airports.
        #
        # @param route [Route] The existing route
        # @param desired_airport_ids [Array<Integer>] The desired airport ids in order
        # @return [Boolean]
        def segments_match?(route, desired_airport_ids)
          route.route_segments.sort_by(&:order).map(&:airport_id) == desired_airport_ids
        end

        # Stages a create for a new route, carrying its segments as nested attributes.
        #
        # @param operator [Operator] The resolved operator
        # @param call_sign [String] The route callsign
        # @param airport_ids [Array<Integer>] The ordered airport ids
        def stage_create(operator, call_sign, airport_ids)
          diff = {
            'operator_id' => [nil, operator.id],
            'call_sign' => [nil, call_sign],
            'route_segments_attributes' => [nil, segment_rows(airport_ids)]
          }

          current_batch.staged_changes.create!(
            record_type: RECORD_TYPE,
            record_identifier: call_sign,
            operation: :create,
            diff: diff
          )
          current_batch.summary['created'] += 1
        end

        # Stages an update that destroys the existing segments and recreates them.
        #
        # @param route [Route] The existing route
        # @param airport_ids [Array<Integer>] The ordered airport ids
        def stage_update(route, airport_ids)
          destroy_rows = route.route_segments.map { |s| { 'id' => s.id, '_destroy' => true } }
          old_repr = route.route_segments.sort_by(&:order)
                          .map { |s| { 'id' => s.id, 'airport_id' => s.airport_id, 'order' => s.order } }

          diff = {
            'route_segments_attributes' => [old_repr, destroy_rows + segment_rows(airport_ids)]
          }

          current_batch.staged_changes.create!(
            record_type: RECORD_TYPE,
            record_id: route.id,
            record_identifier: route.call_sign,
            operation: :update,
            diff: diff
          )
          current_batch.summary['updated'] += 1
        end

        # Builds ordered nested-attribute rows for new segments.
        #
        # @param airport_ids [Array<Integer>] The ordered airport ids
        # @return [Array<Hash>]
        def segment_rows(airport_ids)
          airport_ids.each_with_index.map do |airport_id, index|
            { 'airport_id' => airport_id, 'order' => index }
          end
        end

        # Logs a skipped route and returns an error hash for the import report.
        #
        # @param source [Source::Route::VRSRouteSource] The skipped source row
        # @param message [String] The reason for skipping
        # @return [Hash]
        def skip(source, message)
          Rails.logger.info "Skipping route #{source.callsign}: #{message}"
          { callsign: source.callsign, airline_code: source.airline_code, error: message }
        end

        # Records skipped routes in an import report for visibility.
        #
        # @param errors [Array<Hash>] The collected skip errors
        def record_errors(errors)
          return if errors.empty?

          Source::SourceImportReport.create!(
            import_errors: errors,
            importer_type: name,
            records_processed: errors.count,
            success: true
          )
        end
      end
    end
  end
end
