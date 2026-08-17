# frozen_string_literal: true

require 'test_helper'

class EnrichmentFlightInformationRegionSerializerTest < ActiveSupport::TestCase
  test 'serialises a flight information region to the v2 shape' do
    result = Enrichment::FlightInformationRegionSerializer.call(flight_information_regions(:melbourne))

    assert_equal({ icao_code: 'YMMM', region: 'Melbourne' }, result)
  end

  test 'returns nil for a nil region' do
    assert_nil Enrichment::FlightInformationRegionSerializer.call(nil)
  end
end
