# frozen_string_literal: true

require 'test_helper'

class Processors::Airport::AirportTest < ActiveSupport::TestCase
  # Track test-created records for cleanup.
  # Use ICAO codes that definitely don't exist in real data or fixtures.
  TEST_ICAO_CODES = %w[ZZZZ YYYY XXXX WWWW TTTT IIII EEEE OOOO CCCC UUUU PPPP NNNN].freeze
  TEST_IATA_CODES = %w[ZZZ YYY XXX WWW].freeze
  TEST_COUNTRY_CODES = %w[ZZ YY XX WW TT].freeze

  setup do
    # Clear staging tables
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clean up only test source records (not ALL sources - that would be slow and destructive).
    # Use specific test ICAO codes to avoid interfering with real data.
    Source::Airport::OurAirportsAirportSource.where(icao_code: TEST_ICAO_CODES).delete_all
    Source::Airport::OurAirportsAirportSource.where(iata_code: TEST_IATA_CODES).delete_all
    Source::Airport::OpenFlightsAirportSource.where(icao_code: TEST_ICAO_CODES).delete_all
    Source::Airport::OpenFlightsAirportSource.where(iata_code: TEST_IATA_CODES).delete_all

    # Clean up any airports with our test codes from previous test runs.
    # Airports have FK to countries, so delete them first.
    Airport.where(icao_code: TEST_ICAO_CODES).delete_all
    Airport.where(iata_code: TEST_IATA_CODES).where(icao_code: nil).delete_all

    # Clean up any test countries
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created records
    Airport.where(icao_code: TEST_ICAO_CODES).delete_all
    Airport.where(iata_code: TEST_IATA_CODES).where(icao_code: nil).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # combine_sources staging tests
  # ---------------------------------------------------------------------------

  test 'combine_sources returns a staged batch' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      name: 'Test Airport',
      country_code: 'ZZ',
      latitude: -33.946111,
      longitude: 151.177222,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal 'pending', result.status
    assert_equal 'Airport', result.entity_type
  end

  test 'combine_sources stages airport creation' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      iata_code: 'ZZZ',
      name: 'Test Airport',
      municipality: 'Test City',
      country_code: 'ZZ',
      latitude: -33.946111,
      longitude: 151.177222,
      elevation: 21,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal 'ZZZZ', change.record_identifier
    assert_equal 'Test Airport', change.new_values['name']

    # Airport should NOT exist yet
    assert_nil Airport.find_by(icao_code: 'ZZZZ')
  end

  test 'combine_sources stages airport update' do
    country = Country.create!(
      iso_2char_code: 'YY',
      iso_3char_code: 'YYY',
      name: 'Update Test Country'
    )

    Airport.create!(
      icao_code: 'YYYY',
      name: 'Old Name',
      country: country,
      latitude: -30.0,
      longitude: 150.0
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'YYYY',
      name: 'New Name',
      municipality: 'New City',
      country_code: 'YY',
      latitude: -31.5,
      longitude: 151.5,
      elevation: 100,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal 'YYYY', change.record_identifier
  end

  test 'combine_sources tracks unchanged records' do
    country = Country.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'Unchanged Test Country'
    )

    Airport.create!(
      icao_code: 'XXXX',
      name: 'Same Name',
      city: 'Same City',
      country: country,
      latitude: -33.0,
      longitude: 151.0,
      altitude: 50,
      timezone: 'Australia/Sydney'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'XXXX',
      name: 'Same Name',
      municipality: 'Same City',
      country_code: 'XX',
      latitude: -33.0,
      longitude: 151.0,
      elevation: 50,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary['unchanged']
  end

  test 'combine_sources accepts triggered_by parameter' do
    user = users(:admin)

    country = Country.create!(
      iso_2char_code: 'WW',
      iso_3char_code: 'WWW',
      name: 'Triggered By Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'WWWW',
      name: 'Test',
      country_code: 'WW',
      latitude: -34.0,
      longitude: 150.0,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  test 'applying batch creates the airport' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      iata_code: 'ZZZ',
      name: 'Test Airport',
      municipality: 'Test City',
      country_code: 'ZZ',
      latitude: -33.946111,
      longitude: 151.177222,
      elevation: 21,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    assert_nil Airport.find_by(icao_code: 'ZZZZ')

    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'ZZZZ')
    assert_not_nil airport
    assert_equal 'Test Airport', airport.name
    assert_equal 'ZZZZ', airport.icao_code
    assert_equal 'ZZZ', airport.iata_code
    assert_equal 'Test City', airport.city
    assert_equal country.id, airport.country_id
    assert_in_delta(-33.946111, airport.latitude, 0.000001)
    assert_in_delta(151.177222, airport.longitude, 0.000001)
    assert_equal 21, airport.altitude.to_i
  end

  test 'applying batch updates existing airport' do
    country = Country.create!(
      iso_2char_code: 'TT',
      iso_3char_code: 'TTT',
      name: 'Update Batch Country'
    )

    Airport.create!(
      icao_code: 'TTTT',
      name: 'Old Name',
      country: country,
      latitude: -30.0,
      longitude: 150.0
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'TTTT',
      name: 'New Name',
      municipality: 'New City',
      country_code: 'TT',
      latitude: -31.5,
      longitude: 151.5,
      elevation: 100,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    # Values should still be old before applying
    assert_equal 'Old Name', Airport.find_by(icao_code: 'TTTT').name

    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'TTTT')
    assert_equal 'New Name', airport.name
    assert_equal 'New City', airport.city
    assert_in_delta(-31.5, airport.latitude, 0.000001)
    assert_in_delta(151.5, airport.longitude, 0.000001)
    assert_equal 100, airport.altitude.to_i
  end

  test 'combine_sources merges multiple sources using trust scores' do
    country = Country.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'Merge Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'XXXX',
      name: 'OurAirports Name',
      municipality: 'OurAirports City',
      country_code: 'XX',
      latitude: -33.0,
      longitude: 151.0,
      elevation: 50,
      import_date: Time.current,
      data: { test: true }
    )
    Source::Airport::OpenFlightsAirportSource.create!(
      icao_code: 'XXXX',
      name: 'OpenFlights Name',
      city: 'OpenFlights City',
      country_code: 'XX',
      latitude: -33.5,
      longitude: 151.5,
      elevation: 75,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'XXXX')
    assert_not_nil airport, 'Expected airport to be created from merged sources'
    # The winning values depend on trust scores - just verify values were chosen
    assert_includes ['OurAirports Name', 'OpenFlights Name'], airport.name
    assert_includes ['OurAirports City', 'OpenFlights City'], airport.city
  end

  test 'combine_sources sets provenance for fields' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Provenance Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'WWWW',
      name: 'Provenance Test',
      municipality: 'Test City',
      country_code: 'ZZ',
      latitude: -34.0,
      longitude: 150.0,
      elevation: 30,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'WWWW')
    assert_not_nil airport.field_provenance, 'Expected provenance to be set'

    # Check that provenance was recorded for the name field.
    name_provenance = airport.field_provenance['name'] || airport.field_provenance[:name]
    assert_not_nil name_provenance, 'Expected provenance to be recorded for the name field'
    assert name_provenance.key?('source_type') || name_provenance.key?(:source_type),
           'Expected provenance to include source_type'
  end

  test 'combine_sources excludes records marked as excluded' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Exclusion Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'IIII',
      name: 'Includable Airport',
      country_code: 'ZZ',
      latitude: -36.0,
      longitude: 148.0,
      import_date: Time.current,
      excluded: false,
      data: { test: true }
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'EEEE',
      name: 'Excluded Airport',
      country_code: 'ZZ',
      latitude: -37.0,
      longitude: 147.0,
      import_date: Time.current,
      excluded: true,
      exclusion_reason: 'Test exclusion',
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    assert Airport.exists?(icao_code: 'IIII'), 'Expected includable airport to be created'
    assert_not Airport.exists?(icao_code: 'EEEE'), 'Expected excluded airport to be skipped'
  end

  test 'combine_sources handles both source types' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Multi-Source Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'OOOO',
      name: 'OurAirports Airport',
      country_code: 'ZZ',
      latitude: -38.0,
      longitude: 146.0,
      import_date: Time.current,
      data: { test: true }
    )
    Source::Airport::OpenFlightsAirportSource.create!(
      icao_code: 'CCCC',
      name: 'OpenFlights Airport',
      country_code: 'ZZ',
      latitude: -39.0,
      longitude: 145.0,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    assert Airport.exists?(icao_code: 'OOOO'), 'Expected OurAirports airport to be created'
    assert Airport.exists?(icao_code: 'CCCC'), 'Expected OpenFlights airport to be created'
  end

  test 'combine_sources links to correct country' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Country Link Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'UUUU',
      name: 'Country Link Test Airport',
      country_code: 'ZZ',
      latitude: -40.0,
      longitude: 144.0,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'UUUU')
    assert_equal country.id, airport.country_id,
                 'Expected airport to be linked to the correct country'
  end

  test 'combine_sources skips airports without valid country' do
    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'PPPP',
      name: 'No Country Airport',
      country_code: 'QQ', # Non-existent country code
      latitude: -41.0,
      longitude: 143.0,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources

    # The batch should have no staged changes since the airport was skipped
    assert_equal 0, batch.staged_changes.count,
                 'Expected no staged changes for airport with invalid country'

    # No airport should be created
    assert_not Airport.exists?(icao_code: 'PPPP'),
               'Expected airport to be skipped when country not found'
  end

  test 'combine_sources handles airports with IATA code only' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'IATA Only Country'
    )

    Source::Airport::OpenFlightsAirportSource.create!(
      iata_code: 'ZZZ',
      icao_code: nil,
      name: 'IATA Only Airport',
      country_code: 'ZZ',
      latitude: -42.0,
      longitude: 142.0,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    airport = Airport.find_by(iata_code: 'ZZZ')
    assert_not_nil airport, 'Expected airport with IATA-only code to be created'
    assert_nil airport.icao_code
    assert_equal 'ZZZ', airport.iata_code
  end

  test 'combine_sources sets timezone from coordinates' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Timezone Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      name: 'Timezone Test Airport',
      country_code: 'ZZ',
      latitude: -33.946111,
      longitude: 151.177222,
      import_date: Time.current,
      data: { test: true }
    )

    batch = Processors::Airport::Airport.combine_sources
    batch.apply!(by: nil)

    airport = Airport.find_by(icao_code: 'ZZZZ')
    assert_not_nil airport.timezone, 'Expected timezone to be set from coordinates'
    assert_equal 'Australia/Sydney', airport.timezone
  end

  # ---------------------------------------------------------------------------
  # combine_one tests (direct save, not staged)
  # ---------------------------------------------------------------------------

  test 'combine_one creates airport for specific ICAO code' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Combine One Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      iata_code: 'ZZZ',
      name: 'Combine One Airport',
      municipality: 'Test City',
      country_code: 'ZZ',
      latitude: -33.0,
      longitude: 151.0,
      elevation: 50,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_one('ZZZZ')

    assert_not_nil result[:airport], 'Expected airport in result'
    assert_equal 'Combine One Airport', result[:airport].name
    assert_equal 'ZZZZ', result[:airport].icao_code
    assert result[:created], 'Expected created flag to be true'
  end

  test 'combine_one updates existing airport' do
    country = Country.create!(
      iso_2char_code: 'YY',
      iso_3char_code: 'YYY',
      name: 'Update One Country'
    )

    Airport.create!(
      icao_code: 'YYYY',
      name: 'Old Airport',
      country: country,
      latitude: -30.0,
      longitude: 150.0
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'YYYY',
      name: 'New Airport',
      municipality: 'New City',
      country_code: 'YY',
      latitude: -31.0,
      longitude: 151.0,
      elevation: 100,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_one('YYYY')

    assert_not_nil result[:airport]
    assert_equal 'New Airport', result[:airport].name
    assert_equal 'New City', result[:airport].city
    assert result[:updated], 'Expected updated flag to be true'
  end

  test 'combine_one returns error when no sources found' do
    result = Processors::Airport::Airport.combine_one('NONEXISTENT')

    assert_not_nil result[:error]
    assert_includes result[:error], 'No sources found'
  end

  test 'combine_one raises error for blank identifier' do
    assert_raises(ArgumentError) do
      Processors::Airport::Airport.combine_one('')
    end
  end

  test 'combine_one normalises identifier to uppercase' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Uppercase Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      name: 'Uppercase Test Airport',
      country_code: 'ZZ',
      latitude: -33.0,
      longitude: 151.0,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_one('zzzz')

    assert_not_nil result[:airport]
    assert_equal 'ZZZZ', result[:airport].icao_code
  end

  test 'combine_one auto-detects ICAO identifier' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Auto-detect ICAO Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      name: 'Auto-detect ICAO Airport',
      country_code: 'ZZ',
      latitude: -33.0,
      longitude: 151.0,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_one('ZZZZ')

    assert_not_nil result[:airport]
    assert_equal 'ZZZZ', result[:airport].icao_code
  end

  test 'combine_one auto-detects IATA identifier' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Auto-detect IATA Country'
    )

    Source::Airport::OpenFlightsAirportSource.create!(
      iata_code: 'ZZZ',
      icao_code: nil,
      name: 'Auto-detect IATA Airport',
      country_code: 'ZZ',
      latitude: -33.0,
      longitude: 151.0,
      import_date: Time.current,
      data: { test: true }
    )

    result = Processors::Airport::Airport.combine_one('ZZZ')

    assert_not_nil result[:airport]
    assert_equal 'ZZZ', result[:airport].iata_code
  end

  test 'combine_one returns unchanged for existing airport with no changes' do
    country = Country.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Unchanged Test Country'
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: 'ZZZZ',
      name: 'Unchanged Airport',
      country_code: 'ZZ',
      latitude: -33.0,
      longitude: 151.0,
      import_date: Time.current,
      data: { test: true }
    )

    # First combine creates the record
    Processors::Airport::Airport.combine_one('ZZZZ')

    # Second combine with same data should show unchanged
    result = Processors::Airport::Airport.combine_one('ZZZZ')

    assert_not_nil result[:airport]
    assert result[:unchanged], 'Expected unchanged flag to be true'
  end
end
