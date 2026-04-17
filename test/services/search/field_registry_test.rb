# frozen_string_literal: true

require 'test_helper'

class SearchFieldRegistryTest < ActiveSupport::TestCase
  test 'returns filterable attributes for Aircraft model' do
    fields = Search::FieldRegistry.fields_for('Aircraft')

    assert_kind_of Array, fields
    assert_includes fields, :registration
    assert_includes fields, :aircraft_manufacturer
    assert_includes fields, :operator
  end

  test 'returns empty array for unknown model' do
    fields = Search::FieldRegistry.fields_for('UnknownModel')

    assert_equal [], fields
  end

  test 'field_names_for returns array of field names as strings' do
    field_names = Search::FieldRegistry.field_names_for('Aircraft')

    assert_includes field_names, 'registration'
    assert_includes field_names, 'aircraft_manufacturer'
    assert_includes field_names, 'operator'
  end

  test 'meilisearch_attribute_for returns field name when valid' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'registration')

    assert_equal 'registration', attr
  end

  test 'meilisearch_attribute_for returns aircraft_manufacturer for that field' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'aircraft_manufacturer')

    assert_equal 'aircraft_manufacturer', attr
  end

  test 'meilisearch_attribute_for returns nil for unknown field' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', 'bogus')

    assert_nil attr
  end

  test 'valid_field? returns true for known fields' do
    assert Search::FieldRegistry.valid_field?('Aircraft', 'aircraft_manufacturer')
    assert Search::FieldRegistry.valid_field?('Aircraft', :aircraft_manufacturer)
  end

  test 'valid_field? returns false for unknown fields' do
    assert_not Search::FieldRegistry.valid_field?('Aircraft', 'bogus')
  end

  test 'suggest_fields returns matching fields' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'air')

    assert(suggestions.any? { |s| s[:value] == 'aircraft_manufacturer' })
  end

  test 'suggest_fields is case insensitive' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'AIR')

    assert(suggestions.any? { |s| s[:value] == 'aircraft_manufacturer' })
  end

  test 'suggest_fields returns empty for no matches' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'xyznonexistent')

    assert_empty suggestions
  end

  test 'registered_models returns all model names' do
    models = Search::FieldRegistry.registered_models

    assert_includes models, 'Aircraft'
    assert_includes models, 'AircraftType'
    assert_includes models, 'Operator'
    assert_includes models, 'Airport'
  end
end
