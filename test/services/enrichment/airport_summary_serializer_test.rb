# frozen_string_literal: true

require 'test_helper'

class EnrichmentAirportSummarySerializerTest < ActiveSupport::TestCase
  test 'serialises a lean airport with its country and float coordinates' do
    result = Enrichment::AirportSummarySerializer.call(airports(:yssy))

    assert_equal 'YSSY', result[:icao_code]
    assert_equal 'SYD', result[:iata_code]
    assert_equal 'Sydney International Airport', result[:name]
    assert_equal 'Sydney', result[:city]
    assert_in_delta(-33.946111, result[:latitude], 0.000001)
    assert_in_delta 151.177222, result[:longitude], 0.000001
    assert_in_delta 13.0, result[:altitude], 0.001
    assert_equal 'Australia/Sydney', result[:timezone]
    assert_equal 'Australia', result[:country][:name]
    assert_not result.key?(:runways)
  end

  test 'returns nil for a nil airport' do
    assert_nil Enrichment::AirportSummarySerializer.call(nil)
  end
end
