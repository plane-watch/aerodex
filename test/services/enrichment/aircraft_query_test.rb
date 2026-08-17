# frozen_string_literal: true

require 'test_helper'

class EnrichmentAircraftQueryTest < ActiveSupport::TestCase
  test 'finds an aircraft by ICAO case-insensitively' do
    expected = aircraft(:one)

    assert_equal expected, Enrichment::AircraftQuery.call(expected.icao.downcase)
    assert_equal expected, Enrichment::AircraftQuery.call(expected.icao.upcase)
  end

  test 'returns nil for an unknown ICAO' do
    assert_nil Enrichment::AircraftQuery.call('ZZZZZZ')
  end

  test 'returns nil for a blank ICAO' do
    assert_nil Enrichment::AircraftQuery.call('')
    assert_nil Enrichment::AircraftQuery.call(nil)
  end
end
