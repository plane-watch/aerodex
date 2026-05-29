# frozen_string_literal: true

require 'test_helper'

class Enrichment::OperatorSerializerTest < ActiveSupport::TestCase
  test 'serialises an operator with its country and a nil parent' do
    result = Enrichment::OperatorSerializer.call(operators(:american_airlines))

    assert_equal 'American Airlines', result[:name]
    assert_equal 'AAL', result[:icao_code]
    assert_equal 'AA', result[:iata_code]
    assert_equal 'United States', result[:country][:name]
    assert_nil result[:parent]
  end

  test 'serialises a shallow parent when present' do
    operator = operators(:american_airlines)
    operator.parent_operator = operators(:united_airlines)

    result = Enrichment::OperatorSerializer.call(operator)

    assert_equal({ name: 'United Airlines', icao_code: 'UAL', iata_code: 'UA' }, result[:parent])
  end

  test 'returns nil for a nil operator' do
    assert_nil Enrichment::OperatorSerializer.call(nil)
  end
end
