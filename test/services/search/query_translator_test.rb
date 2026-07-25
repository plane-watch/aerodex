# frozen_string_literal: true

require 'test_helper'

class SearchQueryTranslatorTest < ActiveSupport::TestCase
  # Basic filter generation

  test 'generates filter for exact field match' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'aircraft_manufacturer = "Boeing"', options[:filter]
  end

  test 'generates filter for multiple field matches with AND' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true),
      Search::SearchToken.new(type: :field_value, field: 'operator', value: 'Qantas', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'aircraft_manufacturer = "Boeing" AND operator = "Qantas"', options[:filter]
  end

  test 'generates negated filter' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true,
                              negated: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'NOT aircraft_manufacturer = "Boeing"', options[:filter]
  end

  # Boolean operators

  test 'respects OR operator between tokens' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true),
      Search::SearchToken.new(type: :boolean_or),
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Airbus', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'aircraft_manufacturer = "Boeing" OR aircraft_manufacturer = "Airbus"', options[:filter]
  end

  # Partial matching

  test 'uses attributesToSearchOn for partial matches' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boe', exact: false)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_includes options[:attributesToSearchOn], 'aircraft_manufacturer'
    assert_nil options[:filter]
  end

  test 'search_query includes partial match values' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boe', exact: false)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')

    assert_equal 'Boe', translator.search_query
  end

  # Mixed queries

  test 'handles mix of exact and partial matches' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true),
      Search::SearchToken.new(type: :field_value, field: 'operator', value: 'Qan', exact: false)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'aircraft_manufacturer = "Boeing"', options[:filter]
    assert_includes options[:attributesToSearchOn], 'operator'
    assert_equal 'Qan', translator.search_query
  end

  # Free text

  test 'search_query includes free text tokens' do
    tokens = [
      Search::SearchToken.new(type: :free_text, value: 'VH-OQA'),
      Search::SearchToken.new(type: :free_text, value: '747')
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')

    assert_equal 'VH-OQA 747', translator.search_query
  end

  # Field validation

  test 'ignores unknown field names' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'unknown_field', value: 'test', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_nil options[:filter]
  end

  test 'field_filters? returns true for valid field tokens' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'aircraft_manufacturer', value: 'Boeing', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')

    assert translator.field_filters?
  end

  test 'field_filters? returns false for unknown fields' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'bogus', value: 'test', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')

    assert_not translator.field_filters?
  end

  # Edge cases

  test 'handles empty tokens array' do
    translator = Search::QueryTranslator.new([], 'Aircraft')
    options = translator.to_meilisearch_options

    assert_empty options
  end

  test 'handles nil tokens' do
    translator = Search::QueryTranslator.new(nil, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_empty options
  end

  test 'escapes quotes in values' do
    tokens = [
      Search::SearchToken.new(type: :field_value, field: 'operator', value: 'Test "Quoted" Name', exact: true)
    ]

    translator = Search::QueryTranslator.new(tokens, 'Aircraft')
    options = translator.to_meilisearch_options

    assert_equal 'operator = "Test \\"Quoted\\" Name"', options[:filter]
  end
end
