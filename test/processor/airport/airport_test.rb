# frozen_string_literal: true

require 'test_helper'

class Processors::Airport::AirportTest < ActiveSupport::TestCase
  setup do
    # Clear any cached data
    Processors::Airport::Airport.clear_caches
  end

  teardown do
    Processors::Airport::Airport.clear_caches
  end

  test 'set_timezone_from_coordinates returns correct timezone for Melbourne Airport' do
    airport = Airport.new(
      icao_code: 'TEST',
      latitude: -37.6733,
      longitude: 144.8433
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Australia/Melbourne', airport.timezone
  end

  test 'set_timezone_from_coordinates returns correct timezone for Heathrow Airport' do
    airport = Airport.new(
      icao_code: 'EGLL',
      latitude: 51.4700,
      longitude: -0.4543
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Europe/London', airport.timezone
  end

  test 'set_timezone_from_coordinates returns correct timezone for Los Angeles Airport' do
    airport = Airport.new(
      icao_code: 'KLAX',
      latitude: 33.9425,
      longitude: -118.4081
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'America/Los_Angeles', airport.timezone
  end

  test 'set_timezone_from_coordinates returns correct timezone for Tokyo Narita' do
    airport = Airport.new(
      icao_code: 'RJAA',
      latitude: 35.7647,
      longitude: 140.3864
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Asia/Tokyo', airport.timezone
  end

  test 'set_timezone_from_coordinates returns correct timezone for Dubai Airport' do
    airport = Airport.new(
      icao_code: 'OMDB',
      latitude: 25.2528,
      longitude: 55.3644
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Asia/Dubai', airport.timezone
  end

  test 'set_timezone_from_coordinates does nothing when latitude is blank' do
    airport = Airport.new(
      icao_code: 'TEST',
      latitude: nil,
      longitude: 144.8433,
      timezone: 'Original/Timezone'
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Original/Timezone', airport.timezone
  end

  test 'set_timezone_from_coordinates does nothing when longitude is blank' do
    airport = Airport.new(
      icao_code: 'TEST',
      latitude: -37.6733,
      longitude: nil,
      timezone: 'Original/Timezone'
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Original/Timezone', airport.timezone
  end

  test 'set_timezone_from_coordinates handles edge cases near timezone boundaries' do
    # Adelaide, Australia - UTC+9:30 timezone
    airport = Airport.new(
      icao_code: 'YPAD',
      latitude: -34.9456,
      longitude: 138.5306
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    assert_equal 'Australia/Adelaide', airport.timezone
  end

  test 'set_timezone_from_coordinates handles airports in ocean territories' do
    # Wake Island
    airport = Airport.new(
      icao_code: 'PWAK',
      latitude: 19.2828,
      longitude: 166.6364
    )

    Processors::Airport::Airport.send(:set_timezone_from_coordinates, airport)

    # Wake Island should return a timezone (Pacific/Wake or similar)
    assert_not_nil airport.timezone
  end

  test 'MERGE_FIELDS does not include timezone' do
    # Timezone is handled separately via coordinate lookup, not merged from sources
    refute_includes Processors::Airport::Airport::MERGE_FIELDS, :timezone
  end

  test 'MERGE_FIELDS includes expected fields' do
    expected_fields = %i[name city latitude longitude altitude]

    expected_fields.each do |field|
      assert_includes Processors::Airport::Airport::MERGE_FIELDS, field,
                      "Expected MERGE_FIELDS to include #{field}"
    end
  end
end