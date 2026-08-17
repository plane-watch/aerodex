# frozen_string_literal: true

require 'test_helper'

class EnrichmentAircraftTypeSerializerTest < ActiveSupport::TestCase
  test 'serialises an aircraft type with its manufacturer and enum category label' do
    # Reached via aircraft(:one) (whose type is the Boeing 737 fixture) to avoid
    # referencing a numbered fixture symbol directly.
    result = Enrichment::AircraftTypeSerializer.call(aircraft(:one).aircraft_type)

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
