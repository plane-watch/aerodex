# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportQueryTest < ActiveSupport::TestCase
  test 'finds an airport by ICAO case-insensitively' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(icao: 'yssy')
    assert_equal expected, Enrichment::AirportQuery.call(icao: 'YSSY')
  end

  test 'finds an airport by IATA case-insensitively' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(iata: 'syd')
  end

  test 'prefers ICAO when both are given' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(icao: 'YSSY', iata: 'NOPE')
  end

  test 'returns nil when neither ICAO nor IATA is given' do
    assert_nil Enrichment::AirportQuery.call(icao: nil, iata: nil)
  end

  test 'returns nil for an unknown code' do
    assert_nil Enrichment::AirportQuery.call(icao: 'ZZZZ')
  end
end
