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

  # Cross-model coverage: each SEARCHABLE_MODEL must expose its own
  # filterable_attributes. A single expectation hash so a regression in
  # any model's index surfaces here rather than in a downstream search test.
  test 'fields_for covers every SEARCHABLE_MODEL with expected attributes' do
    expectations = {
      'Operator' => %i[id name icao_code iata_code country],
      'AircraftType' => %i[id name type_code manufacturer category],
      'Airport' => %i[id name city icao_code iata_code country],
      'Country' => %i[id name iso_2char_code iso_3char_code capital],
      'Manufacturer' => %i[id name icao_code country],
      'Route' => %i[id call_sign operator]
    }

    expectations.each do |model_name, expected_fields|
      actual_fields = Search::FieldRegistry.fields_for(model_name)

      assert_equal expected_fields.sort, actual_fields.sort,
                   "expected #{model_name} filterable_attributes to be #{expected_fields.inspect}"
    end
  end

  test 'fields_for returns Symbols, not Strings' do
    fields = Search::FieldRegistry.fields_for('Aircraft')

    assert(fields.all?(Symbol), "expected all Symbols, got #{fields.map(&:class).uniq.inspect}")
  end

  # The registry swallows errors from Meilisearch's settings lookup so that
  # an indexing misconfiguration in one model doesn't take down all field
  # introspection (e.g., search autocomplete). Verify the rescue path by
  # temporarily replacing `meilisearch_settings` with a raising version.
  test 'fields_for returns empty array when the model raises' do
    original_method = Aircraft.method(:meilisearch_settings)
    Aircraft.define_singleton_method(:meilisearch_settings) { raise StandardError, 'boom' }

    assert_equal [], Search::FieldRegistry.fields_for('Aircraft')
  ensure
    Aircraft.define_singleton_method(:meilisearch_settings, original_method) if original_method
  end

  test 'meilisearch_attribute_for accepts Symbol input' do
    attr = Search::FieldRegistry.meilisearch_attribute_for('Aircraft', :registration)

    assert_equal 'registration', attr
  end

  test 'suggest_fields returns results sorted by value' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'a')
    values = suggestions.map { |s| s[:value] }

    assert_equal values.sort, values, "expected alphabetical order, got #{values.inspect}"
  end

  test 'suggest_fields produces a humanised display label' do
    suggestions = Search::FieldRegistry.suggest_fields('Aircraft', 'aircraft_manufacturer')
    manufacturer = suggestions.find { |s| s[:value] == 'aircraft_manufacturer' }

    refute_nil manufacturer, 'expected aircraft_manufacturer in suggestions'
    assert_equal 'Aircraft Manufacturer', manufacturer[:display]
  end
end
