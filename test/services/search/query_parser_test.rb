# frozen_string_literal: true

require 'test_helper'

class SearchQueryParserTest < ActiveSupport::TestCase
  # Basic field:value parsing

  test 'parses simple field:value token' do
    parser = Search::QueryParser.new('manufacturer:Boeing')
    tokens = parser.parse

    assert_equal 1, tokens.length
    assert_equal :field_value, tokens.first.type
    assert_equal 'manufacturer', tokens.first.field
    assert_equal 'Boeing', tokens.first.value
    assert tokens.first.exact?
    assert_not tokens.first.negated?
  end

  test 'parses field name as lowercase' do
    parser = Search::QueryParser.new('MANUFACTURER:Boeing')
    tokens = parser.parse

    assert_equal 'manufacturer', tokens.first.field
  end

  test 'parses field with underscores' do
    parser = Search::QueryParser.new('aircraft_type:A320')
    tokens = parser.parse

    assert_equal 'aircraft_type', tokens.first.field
    assert_equal 'A320', tokens.first.value
  end

  # Quoted values

  test 'parses quoted exact value' do
    parser = Search::QueryParser.new('manufacturer:"Boeing Commercial"')
    tokens = parser.parse

    assert_equal 'Boeing Commercial', tokens.first.value
    assert tokens.first.exact?
  end

  test 'parses quoted value with spaces' do
    parser = Search::QueryParser.new('operator:"Qantas Airways Limited"')
    tokens = parser.parse

    assert_equal 'Qantas Airways Limited', tokens.first.value
  end

  test 'handles empty quoted value' do
    parser = Search::QueryParser.new('manufacturer:""')
    tokens = parser.parse

    assert_equal 1, tokens.length
    assert_equal '', tokens.first.value
  end

  # Partial matching (asterisk suffix)

  test 'parses partial match with asterisk suffix' do
    parser = Search::QueryParser.new('manufacturer:Boe*')
    tokens = parser.parse

    assert_equal 'Boe', tokens.first.value
    assert tokens.first.partial?
    assert_not tokens.first.exact?
  end

  test 'parses partial match in quoted value' do
    parser = Search::QueryParser.new('manufacturer:"Boeing*"')
    tokens = parser.parse

    assert_equal 'Boeing', tokens.first.value
    assert tokens.first.partial?
  end

  # Negation

  test 'parses negated field with dash prefix' do
    parser = Search::QueryParser.new('-manufacturer:Boeing')
    tokens = parser.parse

    assert tokens.first.negated?
    assert_equal 'manufacturer', tokens.first.field
    assert_equal 'Boeing', tokens.first.value
  end

  test 'parses NOT keyword negation' do
    parser = Search::QueryParser.new('NOT manufacturer:Boeing')
    tokens = parser.parse

    assert tokens.first.negated?
    assert_equal 'manufacturer', tokens.first.field
  end

  test 'NOT keyword is case insensitive' do
    parser = Search::QueryParser.new('not manufacturer:Boeing')
    tokens = parser.parse

    assert tokens.first.negated?
  end

  # Multiple tokens

  test 'parses multiple field:value pairs' do
    parser = Search::QueryParser.new('manufacturer:Boeing operator:Qantas')
    tokens = parser.parse

    assert_equal 2, tokens.length
    assert_equal 'manufacturer', tokens[0].field
    assert_equal 'Boeing', tokens[0].value
    assert_equal 'operator', tokens[1].field
    assert_equal 'Qantas', tokens[1].value
  end

  test 'parses mixed field:value and free text' do
    parser = Search::QueryParser.new('manufacturer:Boeing VH-OQA')
    tokens = parser.parse

    field_tokens = tokens.select(&:field_qualified?)
    text_tokens = tokens.select(&:free_text?)

    assert_equal 1, field_tokens.length
    assert_equal 1, text_tokens.length
    assert_equal 'manufacturer', field_tokens.first.field
    assert_equal 'VH-OQA', text_tokens.first.value
  end

  # Boolean operators

  test 'parses AND operator between tokens' do
    parser = Search::QueryParser.new('manufacturer:Boeing AND operator:Qantas')
    tokens = parser.parse

    # Should have: field_value, boolean_and, field_value
    field_tokens = tokens.select(&:field_qualified?)
    boolean_tokens = tokens.select(&:boolean_operator?)

    assert_equal 2, field_tokens.length
    assert_equal 1, boolean_tokens.length
    assert_equal :boolean_and, boolean_tokens.first.type
  end

  test 'parses OR operator between tokens' do
    parser = Search::QueryParser.new('manufacturer:Boeing OR manufacturer:Airbus')
    tokens = parser.parse

    boolean_tokens = tokens.select(&:boolean_operator?)

    assert_equal 1, boolean_tokens.length
    assert_equal :boolean_or, boolean_tokens.first.type
  end

  test 'AND/OR are case insensitive' do
    parser = Search::QueryParser.new('manufacturer:Boeing and operator:Qantas or registration:VH*')
    tokens = parser.parse

    boolean_tokens = tokens.select(&:boolean_operator?)
    assert_equal 2, boolean_tokens.length
  end

  # Free text

  test 'parses free text when no qualifiers' do
    parser = Search::QueryParser.new('Boeing 737')
    tokens = parser.parse

    assert tokens.all?(&:free_text?)
    assert_equal 2, tokens.length
    assert_equal 'Boeing', tokens[0].value
    assert_equal '737', tokens[1].value
  end

  test 'parses quoted free text' do
    parser = Search::QueryParser.new('"Boeing 737"')
    tokens = parser.parse

    assert_equal 1, tokens.length
    assert tokens.first.free_text?
    assert_equal 'Boeing 737', tokens.first.value
  end

  # Helper methods

  test 'has_field_qualifiers? returns true when field tokens present' do
    parser = Search::QueryParser.new('manufacturer:Boeing')

    assert parser.has_field_qualifiers?
  end

  test 'has_field_qualifiers? returns false for free text only' do
    parser = Search::QueryParser.new('Boeing 737')

    assert_not parser.has_field_qualifiers?
  end

  test 'free_text_query combines free text tokens' do
    parser = Search::QueryParser.new('manufacturer:Boeing VH-OQA 747')

    assert_equal 'VH-OQA 747', parser.free_text_query
  end

  test 'field_tokens returns only field-qualified tokens' do
    parser = Search::QueryParser.new('manufacturer:Boeing VH-OQA operator:Qantas')

    field_tokens = parser.field_tokens

    assert_equal 2, field_tokens.length
    assert field_tokens.all?(&:field_qualified?)
  end

  # Edge cases

  test 'handles empty query' do
    parser = Search::QueryParser.new('')
    tokens = parser.parse

    assert_empty tokens
  end

  test 'handles nil query' do
    parser = Search::QueryParser.new(nil)
    tokens = parser.parse

    assert_empty tokens
  end

  test 'handles whitespace-only query' do
    parser = Search::QueryParser.new('   ')
    tokens = parser.parse

    assert_empty tokens
  end

  test 'ignores incomplete field: without value' do
    parser = Search::QueryParser.new('manufacturer:')
    tokens = parser.parse

    # The incomplete pattern should not produce a field token
    assert_empty tokens.select(&:field_qualified?)
  end

  test 'handles complex query with all features' do
    parser = Search::QueryParser.new('manufacturer:Boeing* AND -operator:"British Airways" VH-OQA')
    tokens = parser.parse

    # Should have: partial manufacturer, AND, negated operator, free text
    field_tokens = tokens.select(&:field_qualified?)
    text_tokens = tokens.select(&:free_text?)

    assert_equal 2, field_tokens.length

    # First field token: manufacturer:Boeing*
    manufacturer_token = field_tokens.find { |t| t.field == 'manufacturer' }
    assert manufacturer_token.partial?
    assert_not manufacturer_token.negated?

    # Second field token: -operator:"British Airways"
    operator_token = field_tokens.find { |t| t.field == 'operator' }
    assert operator_token.negated?
    assert operator_token.exact?
    assert_equal 'British Airways', operator_token.value

    # Free text
    assert_equal 1, text_tokens.length
    assert_equal 'VH-OQA', text_tokens.first.value
  end
end
