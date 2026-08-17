# frozen_string_literal: true

require 'test_helper'

class EnrichmentAirportSerializerTest < ActiveSupport::TestCase
  test 'serialises an airport with country, FIR and runways' do
    result = Enrichment::AirportSerializer.call(airports(:yssy))

    assert_equal 'YSSY', result[:icao_code]
    assert_equal 'SYD', result[:iata_code]
    assert_equal '94719', result[:wmo_code]
    assert_equal 'Sydney International Airport', result[:name]
    assert_equal 'Sydney', result[:city]
    assert_in_delta(-33.946111, result[:latitude], 0.000001)
    assert_in_delta 13.0, result[:altitude], 0.001
    assert_equal 'Australia/Sydney', result[:timezone]
    assert_equal 'Australia', result[:country][:name]
    assert_equal({ icao_code: 'YMMM', region: 'Melbourne' }, result[:flight_information_region])

    runway_names = result[:runways].map { |r| r[:name] }
    assert_includes runway_names, '16R'
    assert_includes runway_names, '25'
  end

  test 'emits a nil flight information region as nil' do
    airport = airports(:yssy)
    airport.flight_information_region = nil

    result = Enrichment::AirportSerializer.call(airport)

    assert_nil result[:flight_information_region]
  end
end
