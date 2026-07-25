# frozen_string_literal: true

require 'test_helper'

class FieldMergerTest < ActiveSupport::TestCase
  setup do
    SourceTrustScore.delete_all
  end

  test 'selects value from highest trust source' do
    # VRS has base_trust 80, OTD has 85 for 'name' field
    vrs_source = OpenStruct.new(
      id: 1,
      name: 'VRS Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    otd_source = OpenStruct.new(
      id: 2,
      name: 'OTD Name',
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [vrs_source, otd_source],
      field: :name,
      entity_type: 'Operator'
    )

    # OpenTravel has 85 trust for name field, VRS has 80
    assert_equal 'OTD Name', merger.best_value
    assert_equal otd_source, merger.best_source
    assert_equal 85, merger.best_confidence
  end

  test 'returns nil when no sources provided' do
    merger = FieldMerger.new(sources: [], field: :name, entity_type: 'Operator')

    assert_nil merger.best_value
    assert_nil merger.best_source
    assert_nil merger.best_confidence
  end

  test 'skips sources with nil values' do
    source_with_value = OpenStruct.new(
      id: 1,
      name: 'Has Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    source_without_value = OpenStruct.new(
      id: 2,
      name: nil,
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [source_with_value, source_without_value],
      field: :name,
      entity_type: 'Operator'
    )

    assert_equal 'Has Name', merger.best_value
  end

  test 'detects conflicts between sources' do
    vrs_source = OpenStruct.new(
      id: 1,
      name: 'VRS Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    otd_source = OpenStruct.new(
      id: 2,
      name: 'OTD Name',
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [vrs_source, otd_source],
      field: :name,
      entity_type: 'Operator'
    )

    assert merger.has_conflict?
  end

  test 'no conflict when values are the same' do
    vrs_source = OpenStruct.new(
      id: 1,
      name: 'Same Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    otd_source = OpenStruct.new(
      id: 2,
      name: 'Same Name',
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [vrs_source, otd_source],
      field: :name,
      entity_type: 'Operator'
    )

    assert_not merger.has_conflict?
  end

  test 'generates provenance hash' do
    source = OpenStruct.new(
      id: 42,
      name: 'Test Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [source],
      field: :name,
      entity_type: 'Operator'
    )

    provenance = merger.provenance_hash

    assert_equal 'VRSDataOperatorSource', provenance['source_type']
    assert_equal 42, provenance['source_id']
    assert_equal 80, provenance['confidence']
    assert provenance['combined_at'].present?
  end

  test 'conflict_details returns structured information' do
    vrs_source = OpenStruct.new(
      id: 1,
      name: 'VRS Name',
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    otd_source = OpenStruct.new(
      id: 2,
      name: 'OTD Name',
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    merger = FieldMerger.new(
      sources: [vrs_source, otd_source],
      field: :name,
      entity_type: 'Operator'
    )

    details = merger.conflict_details

    assert_equal 'name', details[:field]
    assert_equal 'Operator', details[:entity_type]
    assert_equal 2, details[:candidates].length
    assert details[:winner].present?
  end
end
