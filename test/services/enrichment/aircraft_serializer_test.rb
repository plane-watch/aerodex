# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftSerializerTest < ActiveSupport::TestCase
  test 'serialises an aircraft with nested type, operator and country' do
    result = Enrichment::AircraftSerializer.call(aircraft(:one))

    assert_equal 'n123456', result[:icao] # lower-cased on output
    assert_equal 'N123456', result[:registration]
    assert_equal '123456', result[:serial_number]
    assert_equal 2023, result[:manufacture_year]
    assert_equal '2023-06-23', result[:registration_date]
    assert_equal 'american_airlines', result[:owner]
    assert_equal 'active', result[:status] # enum label, default 0
    assert_equal 2, result[:engine_count]
    assert_equal 'CFM56-7B27', result[:engine_model]
    assert_equal 'B737', result[:type][:type_code]
    assert_equal 'American Airlines', result[:operator][:name]
    assert_equal 'United States', result[:registration_country][:name]
  end

  test 'leaves a nil operator as nil' do
    aircraft_record = aircraft(:one)
    aircraft_record.operator = nil

    result = Enrichment::AircraftSerializer.call(aircraft_record)

    assert_nil result[:operator]
  end

  test 'emits a nil registration_date as nil' do
    aircraft_record = aircraft(:one)
    aircraft_record.registration_date = nil

    result = Enrichment::AircraftSerializer.call(aircraft_record)

    assert_nil result[:registration_date]
  end
end
