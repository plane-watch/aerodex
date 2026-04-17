# frozen_string_literal: true

require 'test_helper'

class SourceConfigTest < ActiveSupport::TestCase
  test 'returns config for known source types' do
    config = SourceConfig.for('VRSDataOperatorSource')

    assert_equal 80, config[:base_trust]
    assert_kind_of Hash, config[:field_overrides]
    assert_kind_of Hash, config[:modifiers]
  end

  test 'returns default config for unknown source types' do
    config = SourceConfig.for('UnknownSource')

    assert_equal SourceConfig::DEFAULT_TRUST, config[:base_trust]
    assert_empty config[:field_overrides]
    assert_empty config[:modifiers]
  end

  test 'strips module prefixes from class names' do
    config = SourceConfig.for('Source::Operator::VRSDataOperatorSource')

    assert_equal 80, config[:base_trust]
  end

  test 'base_trust_for returns the base trust for a source' do
    assert_equal 80, SourceConfig.base_trust_for('VRSDataOperatorSource')
    assert_equal 70, SourceConfig.base_trust_for('OpenTravelOperatorSource')
  end

  test 'trust_for_field returns field override when present' do
    assert_equal 85, SourceConfig.trust_for_field('OpenTravelOperatorSource', :name)
  end

  test 'trust_for_field returns base trust when no field override' do
    assert_equal 80, SourceConfig.trust_for_field('VRSDataOperatorSource', :name)
  end

  test 'configured? returns true for known sources' do
    assert SourceConfig.configured?('VRSDataOperatorSource')
    assert_not SourceConfig.configured?('UnknownSource')
  end

  test 'all_sources returns all configured source types' do
    sources = SourceConfig.all_sources

    assert_includes sources, 'VRSDataOperatorSource'
    assert_includes sources, 'OpenTravelOperatorSource'
    assert_includes sources, 'CASAAircraftSource'
  end

  test 'CASA config has field overrides for operator and owner' do
    config = SourceConfig.for('CASAAircraftSource')

    assert_equal 85, config[:field_overrides][:operator]
    assert_equal 95, config[:field_overrides][:owner]
    assert_equal 85, config[:base_trust]
  end

  test 'CASA config has ICAO modifier' do
    config = SourceConfig.for('CASAAircraftSource')

    assert config[:modifiers].key?(:icao)
    assert config[:modifiers][:icao][:filter].respond_to?(:call)
    assert config[:modifiers][:icao][:adjust].respond_to?(:call)
  end
end