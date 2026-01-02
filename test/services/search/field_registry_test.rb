# frozen_string_literal: true

require 'test_helper'

class SearchFieldRegistryTest < ActiveSupport::TestCase
  test 'returns fields for Aircraft model' do
    fields = Search::FieldRegistry.fields_for('Aircraft')

    assert fields.key?(:manufacturer)
    assert fields.key?(:operator)
    assert fields.key?(:registration)
  end

  test 'returns empty hash for unknown model' do
    fields = Search::FieldRegistry.fields_for('UnknownModel')

    assert_equal({}, fields)
  end

  test 'field_names_for returns array of field names' do
    field_names = Search::FieldRegistry.field_names_for('Aircraft')

    assert_includes field_names, 'manufacturer'
    assert_includes field_names, 'operator'
    assert_includes field_names, 'registration'
  end

  test 'meilisearch_attribute_for returns correct mapping' do
    # manufacturer field maps to aircraft_manufacturer in Meilisearch
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'manufacturer')

    assert_equal 'aircraft_manufacturer', attr
  end

  test 'meilisearch_attribute_for returns direct mapping for non-associated fields' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'registration')

    assert_equal 'registration', attr
  end

  test 'meilisearch_attribute_for returns nil for unknown field' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'bogus')

    assert_nil attr
  end

  test 'valid_field? returns true for known fields' do
    assert Search::FieldRegistry.valid_field?('Aircraft', 'manufacturer')
    assert Search::FieldRegistry.valid_field?('Aircraft', :manufacturer)
  end

  test 'valid_field? returns false for unknown fields' do
    assert_not Search::FieldRegistry.valid_field?('Aircraft', 'bogus')
  end

  test 'suggest_fields returns matching fields' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'man')

    assert_equal 1, suggestions.length
    assert_equal 'manufacturer', suggestions.first[:value]
    assert_equal 'Manufacturer', suggestions.first[:display]
  end

  test 'suggest_fields is case insensitive' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'MAN')

    assert_equal 1, suggestions.length
    assert_equal 'manufacturer', suggestions.first[:value]
  end

  test 'suggest_fields returns empty for no matches' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'xyz')

    assert_empty suggestions
  end

  test 'registered_models returns all model names' do
    models = Search::FieldRegistry.registered_models

    assert_includes models, 'Aircraft'
    assert_includes models, 'AircraftType'
    assert_includes models, 'Operator'
    assert_includes models, 'Airport'
  end

  test 'field_config_for returns FieldConfig struct' do
    config = Search::FieldRegistry.field_config_for('Aircraft', 'manufacturer')

    assert_instance_of Search::FieldRegistry::FieldConfig, config
    assert_equal 'aircraft_manufacturer', config.meilisearch_attribute
    assert_equal 'Manufacturer', config.display_name
    assert_equal :string, config.type
    assert_equal :association, config.source
  end
end
