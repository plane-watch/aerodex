# frozen_string_literal: true

require 'test_helper'
require 'ostruct'

class HasFieldProvenanceTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:american_airlines)
    @operator.field_provenance = {}

    # Create a mock source for provenance tracking
    @mock_source = OpenStruct.new(
      id: 42,
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )
  end

  test 'set_provenance stores provenance data for a field' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    provenance = @operator.field_provenance['name']
    assert_equal 'VRSDataOperatorSource', provenance['source_type']
    assert_equal 42, provenance['source_id']
    assert_equal 85, provenance['confidence']
    assert provenance['combined_at'].present?
  end

  test 'provenance_for returns the provenance hash for a field' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    provenance = @operator.provenance_for(:name)

    assert_kind_of Hash, provenance
    assert_equal 'VRSDataOperatorSource', provenance['source_type']
  end

  test 'provenance_for returns nil for a field without provenance' do
    assert_nil @operator.provenance_for(:nonexistent_field)
  end

  test 'provenance_source_for returns the source class name' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    assert_equal 'VRSDataOperatorSource', @operator.provenance_source_for(:name)
  end

  test 'provenance_confidence_for returns the confidence score' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    assert_equal 85, @operator.provenance_confidence_for(:name)
  end

  test 'provenance_source_id_for returns the source record ID' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    assert_equal 42, @operator.provenance_source_id_for(:name)
  end

  test 'provenance_combined_at_for returns a Time object' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    combined_at = @operator.provenance_combined_at_for(:name)

    assert_kind_of Time, combined_at
    assert_in_delta Time.current, combined_at, 2
  end

  test 'set_provenance_for_fields sets provenance for multiple fields' do
    @operator.set_provenance_for_fields(
      %i[name icao_code],
      source: @mock_source,
      confidence: 80
    )

    assert @operator.has_provenance?(:name)
    assert @operator.has_provenance?(:icao_code)
    assert_equal 80, @operator.provenance_confidence_for(:name)
    assert_equal 80, @operator.provenance_confidence_for(:icao_code)
  end

  test 'clear_provenance removes provenance for a field' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)
    assert @operator.has_provenance?(:name)

    @operator.clear_provenance(:name)

    assert_not @operator.has_provenance?(:name)
  end

  test 'tracked_fields returns all fields with provenance' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)
    @operator.set_provenance(:icao_code, source: @mock_source, confidence: 80)

    tracked = @operator.tracked_fields

    assert_includes tracked, 'name'
    assert_includes tracked, 'icao_code'
    assert_equal 2, tracked.length
  end

  test 'has_provenance? returns true when field has provenance' do
    @operator.set_provenance(:name, source: @mock_source, confidence: 85)

    assert @operator.has_provenance?(:name)
    assert @operator.has_provenance?('name')
  end

  test 'has_provenance? returns false when field lacks provenance' do
    assert_not @operator.has_provenance?(:name)
  end

  test 'provenance accepts string or symbol field names' do
    @operator.set_provenance('name', source: @mock_source, confidence: 85)

    # Should be accessible via symbol
    assert_equal 85, @operator.provenance_confidence_for(:name)
    # And via string
    assert_equal 85, @operator.provenance_confidence_for('name')
  end

  test 'set_provenance overwrites existing provenance for a field' do
    other_source = OpenStruct.new(
      id: 99,
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    @operator.set_provenance(:name, source: @mock_source, confidence: 85)
    @operator.set_provenance(:name, source: other_source, confidence: 90)

    assert_equal 'OpenTravelOperatorSource', @operator.provenance_source_for(:name)
    assert_equal 99, @operator.provenance_source_id_for(:name)
    assert_equal 90, @operator.provenance_confidence_for(:name)
  end

  test 'mark_combined! updates the last_combined_at timestamp' do
    @operator.save!

    assert_nil @operator.last_combined_at

    @operator.mark_combined!

    @operator.reload
    assert_not_nil @operator.last_combined_at
    assert_in_delta Time.current, @operator.last_combined_at, 2
  end
end
