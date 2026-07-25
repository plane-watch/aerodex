# frozen_string_literal: true

require 'test_helper'

class TrustCalculatorTest < ActiveSupport::TestCase
  setup do
    SourceTrustScore.delete_all
    SourceTrustScore.clear_cache!
  end

  test 'calculates trust from SourceConfig when no database override' do
    source = fake_source('Source::Operator::VRSDataOperatorSource')

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

    source = fake_source('Source::Operator::VRSDataOperatorSource')

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    assert_equal 95, calculator.calculate
  end

  test 'uses SourceConfig field override when present' do
    source = fake_source('Source::Operator::OpenTravelOperatorSource')

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    # OpenTravelOperatorSource has name field override of 85
    assert_equal 85, calculator.calculate
  end

  test 'returns source_type as demodulized class name' do
    source = fake_source('Source::Operator::VRSDataOperatorSource')

    calculator = TrustCalculator.new(source, field: :name, entity_type: 'Operator')

    assert_equal 'VRSDataOperatorSource', calculator.source_type
  end

  private

  # Builds a lightweight fake source record whose real class reports the
  # given name via `class.name`. Overriding `Object#class` directly would
  # break `is_a?`, `case..when`, and pattern matching on the fake, so we
  # use an anonymous class with a custom `.name` instead.
  def fake_source(class_name)
    klass = Class.new
    klass.define_singleton_method(:name) { class_name }
    source = klass.new
    source.define_singleton_method(:id) { 1 }
    source
  end
end
