# frozen_string_literal: true

require 'test_helper'

module Processors
  module Route
    class RouteTest < ActiveSupport::TestCase
      setup do
        Source::Route::VRSRouteSource.delete_all
        # Delete staged changes before batches to avoid the foreign-key
        # violation from the staged_changes fixtures referencing staged_batches.
        StagedChange.delete_all
        StagedBatch.delete_all
        @qantas = operators(:qantas)
        @yssy = airports(:yssy)
        @wsss = airports(:wsss)
        @egll = airports(:egll)
      end

      def create_source(attrs = {})
        Source::Route::VRSRouteSource.create!(
          {
            callsign: 'QFA1',
            airline_code: 'QFA',
            airport_codes: 'YSSY-WSSS-EGLL',
            import_date: Time.current
          }.merge(attrs)
        )
      end

      test 'stages a create for a resolvable new route' do
        create_source

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        change = batch.staged_changes.first
        assert_equal 'Route', change.record_type
        assert_equal 'create', change.operation
        assert_equal 'QFA1', change.record_identifier

        segments = change.new_values['route_segments_attributes']
        airport_ids = segments.map { |s| s['airport_id'] }
        orders = segments.map { |s| s['order'] }
        assert_equal [@yssy.id, @wsss.id, @egll.id], airport_ids
        assert_equal [0, 1, 2], orders
      end

      test 'applying the batch creates the route with ordered segments' do
        create_source
        batch = Processors::Route::Route.combine_sources

        batch.apply!(by: nil)

        route = ::Route.find_by(operator: @qantas, call_sign: 'QFA1')
        assert_not_nil route
        assert_equal [@yssy.id, @wsss.id, @egll.id],
                     route.route_segments.order(:order).map(&:airport_id)
      end

      test 'skips the route and stages nothing when the operator is unresolved' do
        create_source(airline_code: 'ZZZ')

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
      end

      test 'skips the whole route when any airport is unresolved' do
        create_source(airport_codes: 'YSSY-XXXX-EGLL')

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
      end

      test 'stages nothing for an unchanged existing route' do
        create_source
        existing = ::Route.create!(
          operator: @qantas, call_sign: 'QFA1',
          route_segments_attributes: [
            { airport_id: @yssy.id, order: 0 },
            { airport_id: @wsss.id, order: 1 },
            { airport_id: @egll.id, order: 2 }
          ]
        )
        assert existing.persisted?

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
        assert_equal 1, batch.summary['unchanged']
      end

      test 'stages an update that replaces segments when they differ' do
        create_source
        ::Route.create!(
          operator: @qantas, call_sign: 'QFA1',
          route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
        )

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        change = batch.staged_changes.first
        assert_equal 'update', change.operation

        batch.apply!(by: nil)
        route = ::Route.find_by(operator: @qantas, call_sign: 'QFA1')
        assert_equal [@yssy.id, @wsss.id, @egll.id],
                     route.route_segments.order(:order).map(&:airport_id)
      end

      test 'airline_code scopes the run to a single airline' do
        create_source(callsign: 'QFA1', airline_code: 'QFA')
        create_source(callsign: 'AAL1', airline_code: 'AAL', airport_codes: 'YSSY-WSSS')

        batch = Processors::Route::Route.combine_sources(airline_code: 'QFA')

        assert_equal 1, batch.staged_changes.count
        assert_equal 'QFA1', batch.staged_changes.first.record_identifier
      end

      test 'resolves the operator and airports by IATA code when ICAO does not match' do
        create_source(callsign: 'QF9', airline_code: 'QF', airport_codes: 'SIN-LHR')

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        change = batch.staged_changes.first
        assert_equal @qantas.id, change.new_values['operator_id']

        segments = change.new_values['route_segments_attributes']
        airport_ids = segments.map { |s| s['airport_id'] }
        assert_equal [@wsss.id, @egll.id], airport_ids
      end

      test 'stages resolvable routes and skips unresolvable ones in the same run' do
        create_source(callsign: 'QFA1', airline_code: 'QFA', airport_codes: 'YSSY-WSSS')
        create_source(callsign: 'ZZZ1', airline_code: 'ZZZ', airport_codes: 'YSSY-WSSS')

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        assert_equal 'QFA1', batch.staged_changes.first.record_identifier
      end

      test 'records skipped routes in a SourceImportReport and the batch notes' do
        Source::SourceImportReport.delete_all
        create_source(callsign: 'ZZZ1', airline_code: 'ZZZ', airport_codes: 'YSSY-WSSS')

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
        assert_equal 1, Source::SourceImportReport.count
        assert_match(/Skipped 1/, batch.notes)
      end
    end
  end
end
