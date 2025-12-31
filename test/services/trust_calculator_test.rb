# frozen_string_literal: true

require 'test_helper'

class TrustCalculatorTest < ActiveSupport::TestCase
  setup do
    SourceTrustScore.delete_all
  end

  test 'calculates trust from SourceConfig when no database override' do
    # Create a mock source record
    source = OpenStruct.new(
      id: 1,
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    # VRSDataOperatorSource base_trust is 80
    assert_equal 80, calculator.calculate
  end

  test 'uses database override when present' do
    SourceTrustScore.create!(
      entity_type: 'Operator',
      source_type: 'VRSDataOperatorSource',
      field_name: 'name',
      base_trust: 95
    )

    source = OpenStruct.new(
      id: 1,
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    assert_equal 95, calculator.calculate
  end

  test 'uses SourceConfig field override when present' do
    source = OpenStruct.new(
      id: 1,
      class: OpenStruct.new(name: 'Source::Operator::OpenTravelOperatorSource')
    )

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    # OpenTravelOperatorSource has name field override of 85
    assert_equal 85, calculator.calculate
  end

  test 'returns source_type as demodulized class name' do
    source = OpenStruct.new(
      id: 1,
      class: OpenStruct.new(name: 'Source::Operator::VRSDataOperatorSource')
    )

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    assert_equal 'VRSDataOperatorSource', calculator.source_type
  end
end