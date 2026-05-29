# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftTypeSerializerTest < ActiveSupport::TestCase
  test 'serialises an aircraft type with its manufacturer and enum category label' do
    result = Enrichment::AircraftTypeSerializer.call(aircraft_types(:boeing_737))

    assert_equal 'B737', result[:type_code]
    assert_equal '737-800', result[:name]
    assert_equal 'Boeing 737-800', result[:full_name]
    assert_equal 'airplane', result[:category]
    assert_equal 'Boeing', result[:manufacturer][:name]
  end

  test 'returns nil for a nil type' do
    assert_nil Enrichment::AircraftTypeSerializer.call(nil)
  end
end
