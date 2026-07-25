# frozen_string_literal: true

require 'test_helper'

class Processors::Runway::RunwayTest < ActiveSupport::TestCase
  # Track test-created records for cleanup.
  # Use identifiers that definitely don't exist in real data or fixtures.
  TEST_ICAO_CODES = %w[ZZZZ YYYY XXXX WWWW].freeze
  TEST_LE_IDENTS = %w[99L 99R 88L 88R 77L 77R].freeze
  TEST_COUNTRY_CODES = %w[ZZ YY].freeze

  setup do
    # Clear staging tables
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clean up only test source records (not ALL sources)
    Source::Runway::OurAirportsRunwaySource.where(airport_ident: TEST_ICAO_CODES).delete_all

    # Clean up any runways for our test airports from previous test runs.
    # Runways have FK to airports, so get the airport IDs first.
    test_airport_ids = Airport.where(icao_code: TEST_ICAO_CODES).pluck(:id)
    AirportRunway.where(airport_id: test_airport_ids).delete_all if test_airport_ids.any?

    # Clean up test airports (they have FK to countries)
    Airport.where(icao_code: TEST_ICAO_CODES).delete_all

    # Clean up any test countries
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created records in reverse FK order
    test_airport_ids = Airport.where(icao_code: TEST_ICAO_CODES).pluck(:id)
    AirportRunway.where(airport_id: test_airport_ids).delete_all if test_airport_ids.any?
    Airport.where(icao_code: TEST_ICAO_CODES).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # Helper methods
  # ---------------------------------------------------------------------------

  # Creates a test country and airport for runway tests
  def create_test_airport(icao_code: 'ZZZZ', country_code: 'ZZ')
    country = Country.find_or_create_by!(iso_2char_code: country_code) do |c|
      c.iso_3char_code = "#{country_code}Z"
      c.name = "Test Country #{country_code}"
    end

    Airport.create!(
      icao_code: icao_code,
      name: "Test Airport #{icao_code}",
      country: country,
      latitude: -33.946111,
      longitude: 151.177222
    )
  end

  # Creates a runway source with sensible defaults and the required data field
  def create_runway_source(attrs = {})
    defaults = {
      airport_ident: 'ZZZZ',
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: false,
      closed: false,
      import_date: Time.current,
      data: { test: true }
    }
    Source::Runway::OurAirportsRunwaySource.create!(defaults.merge(attrs))
  end

  # ---------------------------------------------------------------------------
  # combine_sources staging tests
  # ---------------------------------------------------------------------------

  test 'combine_sources returns a staged batch' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASP'
    )

    result = Processors::Runway::Runway.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal 'pending', result.status
    assert_equal 'Runway', result.entity_type
  end

  test 'combine_sources stages runway creation' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false,
      le_heading_deg: 170
    )

    batch = Processors::Runway::Runway.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal 'ZZZZ/99L', change.record_identifier
    assert_equal '99L', change.new_values['le_ident']

    # Runway should NOT exist yet
    assert_nil AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
  end

  test 'applying batch creates the runway' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false,
      le_heading_deg: 170
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert_not_nil runway, 'Expected runway to be created'
    assert_equal '99L', runway.le_ident
    assert_equal '17R', runway.he_ident
    assert_equal airport.id, runway.airport_id
    assert runway.lighted, 'Expected runway to be lighted'
    assert_not runway.closed, 'Expected runway to not be closed'
  end

  test 'combine_sources stages runway update' do
    airport = create_test_airport

    # Create an existing runway record
    existing_runway = AirportRunway.create!(
      airport: airport,
      le_ident: '99L',
      he_ident: '17R',
      length: 3000,
      width: 40,
      surface: 'grass',
      lighted: false,
      closed: true
    )

    # Create a source with updated data
    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false,
      le_heading_deg: 170
    )

    batch = Processors::Runway::Runway.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal 'ZZZZ/99L', change.record_identifier
  end

  test 'applying batch updates existing runway' do
    airport = create_test_airport

    # Create an existing runway record
    existing_runway = AirportRunway.create!(
      airport: airport,
      le_ident: '99L',
      he_ident: '17R',
      length: 3000,
      width: 40,
      surface: 'grass',
      lighted: false,
      closed: true
    )

    # Create a source with updated data
    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false,
      le_heading_deg: 170
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find(existing_runway.id)
    assert runway.lighted, 'Expected runway lighted to be updated'
    assert_not runway.closed, 'Expected runway closed to be updated'
    assert_equal 'asphalt', runway.surface
  end

  test 'combine_sources links to correct airport via ICAO code' do
    airport1 = create_test_airport(icao_code: 'ZZZZ', country_code: 'ZZ')
    airport2 = create_test_airport(icao_code: 'YYYY', country_code: 'YY')

    # Create sources for different airports
    create_runway_source(
      airport_ident: 'ZZZZ',
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASP'
    )
    create_runway_source(
      airport_ident: 'YYYY',
      le_ident: '88L',
      he_ident: '26R',
      length_ft: 8000,
      width_ft: 100,
      surface: 'CON'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    # Check runways are linked to correct airports
    runway1 = AirportRunway.find_by(le_ident: '99L')
    runway2 = AirportRunway.find_by(le_ident: '88L')

    assert_equal airport1.id, runway1.airport_id, 'Expected runway to be linked to correct airport'
    assert_equal airport2.id, runway2.airport_id, 'Expected runway to be linked to correct airport'
  end

  test 'combine_sources skips runways for unknown airports' do
    # Don't create an airport for this ICAO code
    create_runway_source(
      airport_ident: 'UNKN',
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASP'
    )

    batch = Processors::Runway::Runway.combine_sources

    # The batch should have no staged changes since the airport wasn't found
    assert_equal 0, batch.staged_changes.count,
                 'Expected no staged changes for runway with unknown airport'
  end

  test 'combine_sources normalises surface type' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASPH' # Should normalise to "asphalt"
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert_equal 'asphalt', runway.surface, 'Expected surface to be normalised'
  end

  test 'combine_sources converts length and width from feet to metres' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 10_000, # ~3048 metres
      width_ft: 150, # ~45.7 metres
      surface: 'ASP'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    # The source model converts feet to metres via length_metres/width_metres methods
    # 10000 ft = 3048.0 metres, 150 ft = 45.7 metres
    assert_in_delta 3048.0, runway.length, 0.1, 'Expected length to be converted to metres'
    assert_in_delta 45.7, runway.width, 0.1, 'Expected width to be converted to metres'
  end

  test 'combine_sources sets runway heading from source' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '16L',
      he_ident: '34R',
      le_heading_deg: 165.5
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '16L')
    assert_in_delta 165.5, runway.heading, 0.1, 'Expected heading to be set from source'
  end

  test 'combine_sources sets runway_name from display_name' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '16L',
      he_ident: '34R'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '16L')
    assert_equal '16L/34R', runway.runway_name, 'Expected runway_name to be set from display_name'
  end

  test 'combine_sources sets provenance for fields' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert_not_nil runway.field_provenance, 'Expected provenance to be set'

    # Check that provenance was recorded for a merged field.
    # Provenance keys can be strings or symbols depending on serialisation.
    length_provenance = runway.field_provenance['length'] || runway.field_provenance[:length]
    assert_not_nil length_provenance, 'Expected provenance to be recorded for the length field'
    assert length_provenance.key?('source_type') || length_provenance.key?(:source_type),
           'Expected provenance to include source_type'
  end

  test 'combine_sources sets last_combined_at timestamp' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R'
    )

    freeze_time do
      batch = Processors::Runway::Runway.combine_sources
      batch.apply!(by: nil)

      runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
      assert_not_nil runway.last_combined_at, 'Expected last_combined_at to be set'
      assert_in_delta Time.current, runway.last_combined_at, 1.second
    end
  end

  test 'combine_sources excludes records marked as excluded' do
    airport = create_test_airport

    # Create an includable source
    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASP',
      excluded: false
    )

    # Create an excluded source (should be ignored)
    create_runway_source(
      le_ident: '88L',
      he_ident: '26R',
      length_ft: 8000,
      width_ft: 100,
      surface: 'CON',
      excluded: true,
      exclusion_reason: 'Test exclusion'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    # The includable runway should exist
    assert AirportRunway.exists?(airport_id: airport.id, le_ident: '99L'),
           'Expected includable runway to be created'

    # The excluded runway should not exist
    assert_not AirportRunway.exists?(airport_id: airport.id, le_ident: '88L'),
               'Expected excluded runway to be skipped'
  end

  test 'combine_sources creates multiple runways for one airport' do
    airport = create_test_airport

    # Create multiple runway sources for the same airport
    create_runway_source(le_ident: '16L', he_ident: '34R', surface: 'ASP')
    create_runway_source(le_ident: '16R', he_ident: '34L', length_ft: 11_500, width_ft: 145, surface: 'ASP')
    create_runway_source(le_ident: '07', he_ident: '25', length_ft: 8000, width_ft: 100, surface: 'CON')

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    # All three runways should be created
    assert_equal 3, AirportRunway.where(airport_id: airport.id).count,
                 'Expected all three runways to be created'
    assert AirportRunway.exists?(airport_id: airport.id, le_ident: '16L')
    assert AirportRunway.exists?(airport_id: airport.id, le_ident: '16R')
    assert AirportRunway.exists?(airport_id: airport.id, le_ident: '07')
  end

  test 'combine_sources handles closed runways' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      lighted: false,
      closed: true
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert runway.closed, 'Expected runway to be marked as closed'
  end

  test 'combine_sources handles unlighted runways' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 5000,
      width_ft: 60,
      surface: 'GRS', # Grass
      lighted: false,
      closed: false
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert_not runway.lighted, 'Expected runway to not be lighted'
    assert_equal 'grass', runway.surface, 'Expected grass surface to be normalised'
  end

  test 'combine_sources tracks unchanged records' do
    airport = create_test_airport

    # Create an existing runway record with same values as source.
    # Note: Must match exactly what the processor produces, including
    # precision of converted values (150 ft = 45.7m, 12000 ft = 3657.6m)
    AirportRunway.create!(
      airport: airport,
      le_ident: '99L',
      he_ident: '17R',
      runway_name: '99L/17R',
      heading: nil,
      length: 3657.6,  # 12000 ft in metres
      width: 45.7,     # 150 ft in metres (note: source rounds to 45.7)
      surface: 'asphalt',
      lighted: true,
      closed: false
    )

    # Create a source with same data (no heading)
    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 12_000,
      width_ft: 150,
      surface: 'ASP',
      lighted: true,
      closed: false,
      le_heading_deg: nil
    )

    batch = Processors::Runway::Runway.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary['unchanged']
  end

  test 'combine_sources accepts triggered_by parameter' do
    user = users(:admin)

    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      surface: 'ASP'
    )

    batch = Processors::Runway::Runway.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  # ---------------------------------------------------------------------------
  # combine_one tests
  # ---------------------------------------------------------------------------

  test 'combine_one creates runway for specific airport and le_ident' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '16L',
      he_ident: '34R',
      lighted: true,
      le_heading_deg: 165
    )

    result = Processors::Runway::Runway.combine_one('ZZZZ', '16L')

    assert_not_nil result[:runway], 'Expected runway in result'
    assert_equal '16L', result[:runway].le_ident
    assert_equal '34R', result[:runway].he_ident
    assert_equal airport.id, result[:runway].airport_id
    assert result[:created], 'Expected created flag to be true'
  end

  test 'combine_one updates existing runway' do
    airport = create_test_airport

    # Create existing runway
    existing_runway = AirportRunway.create!(
      airport: airport,
      le_ident: '16L',
      he_ident: '34R',
      length: 3000,
      width: 40,
      surface: 'grass',
      lighted: false
    )

    # Create source with updated data
    create_runway_source(
      le_ident: '16L',
      he_ident: '34R',
      surface: 'ASP',
      lighted: true,
      le_heading_deg: 165
    )

    result = Processors::Runway::Runway.combine_one('ZZZZ', '16L')

    assert_not_nil result[:runway]
    assert_equal existing_runway.id, result[:runway].id
    assert_equal 'asphalt', result[:runway].surface
    assert result[:runway].lighted
    assert result[:updated], 'Expected updated flag to be true'
  end

  test 'combine_one returns error when airport not found' do
    result = Processors::Runway::Runway.combine_one('UNKN', '16L')

    assert_not_nil result[:error]
    assert_includes result[:error], 'Airport not found'
  end

  test 'combine_one returns error when no sources found' do
    create_test_airport # Create the airport but no runway sources

    result = Processors::Runway::Runway.combine_one('ZZZZ', '16L')

    assert_not_nil result[:error]
    assert_includes result[:error], 'No runway sources found'
  end

  test 'combine_one raises error for blank airport ICAO' do
    assert_raises(ArgumentError) do
      Processors::Runway::Runway.combine_one('')
    end

    assert_raises(ArgumentError) do
      Processors::Runway::Runway.combine_one('   ')
    end
  end

  test 'combine_one normalises airport ICAO to uppercase' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '16L',
      he_ident: '34R'
    )

    # Pass lowercase code - should still work
    result = Processors::Runway::Runway.combine_one('zzzz', '16L')

    assert_not_nil result[:runway]
    assert_equal airport.id, result[:runway].airport_id
  end

  test 'combine_one combines all runways at airport when le_ident is nil' do
    airport = create_test_airport

    # Create multiple runway sources
    create_runway_source(le_ident: '16L', he_ident: '34R')
    create_runway_source(le_ident: '07', he_ident: '25', length_ft: 8000, width_ft: 100, surface: 'CON')

    result = Processors::Runway::Runway.combine_one('ZZZZ')

    assert_not_nil result[:runways], 'Expected runways array in result'
    assert_equal 2, result[:runways].length, 'Expected two runways to be combined'

    # Check that the runways array contains runway results (not raw records)
    runway_le_idents = result[:runways].map { |r| r[:runway]&.le_ident }.compact
    assert_includes runway_le_idents, '16L'
    assert_includes runway_le_idents, '07'
  end

  test 'combine_one trims whitespace from airport ICAO' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '16L',
      he_ident: '34R'
    )

    # Pass code with whitespace - should still work
    result = Processors::Runway::Runway.combine_one('  ZZZZ  ', '16L')

    assert_not_nil result[:runway]
    assert_equal airport.id, result[:runway].airport_id
  end

  # ---------------------------------------------------------------------------
  # Composite key tests (airport_id + le_ident)
  # ---------------------------------------------------------------------------

  test 'composite key distinguishes runways at same airport' do
    airport = create_test_airport

    # Create two runway sources with different le_idents
    create_runway_source(le_ident: '16L', he_ident: '34R')
    create_runway_source(le_ident: '16R', he_ident: '34L', length_ft: 11_500, width_ft: 145)

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    # Both runways should exist as separate records
    runway_16l = AirportRunway.find_by(airport_id: airport.id, le_ident: '16L')
    runway_16r = AirportRunway.find_by(airport_id: airport.id, le_ident: '16R')

    assert_not_nil runway_16l
    assert_not_nil runway_16r
    assert_not_equal runway_16l.id, runway_16r.id, 'Expected different records for different le_idents'
  end

  test 'composite key allows same le_ident at different airports' do
    airport1 = create_test_airport(icao_code: 'ZZZZ', country_code: 'ZZ')
    airport2 = create_test_airport(icao_code: 'YYYY', country_code: 'YY')

    # Create runway sources with same le_ident but different airports
    create_runway_source(
      airport_ident: 'ZZZZ',
      le_ident: '16L',
      he_ident: '34R',
      length_ft: 12_000,
      surface: 'ASP'
    )
    create_runway_source(
      airport_ident: 'YYYY',
      le_ident: '16L',
      he_ident: '34R',
      length_ft: 10_000,
      width_ft: 120,
      surface: 'CON'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    # Both runways should exist as separate records
    runway1 = AirportRunway.find_by(airport_id: airport1.id, le_ident: '16L')
    runway2 = AirportRunway.find_by(airport_id: airport2.id, le_ident: '16L')

    assert_not_nil runway1
    assert_not_nil runway2
    assert_not_equal runway1.id, runway2.id, 'Expected different records for different airports'
    assert_in_delta 3657.6, runway1.length, 0.1  # 12000 ft in metres
    assert_in_delta 3048.0, runway2.length, 0.1  # 10000 ft in metres
  end

  # ---------------------------------------------------------------------------
  # Surface normalisation tests
  # ---------------------------------------------------------------------------

  test 'combine_sources normalises various surface types' do
    airport = create_test_airport

    surface_tests = {
      '99L' => { source: 'ASPH', expected: 'asphalt' },
      '88L' => { source: 'CONCRETE', expected: 'concrete' },
      '77L' => { source: 'GRS', expected: 'grass' },
      '99R' => { source: 'GRAVEL', expected: 'gravel' },
      '88R' => { source: 'TURF', expected: 'turf' },
      '77R' => { source: 'WATER', expected: 'water' }
    }

    surface_tests.each do |le_ident, test_data|
      create_runway_source(
        le_ident: le_ident,
        he_ident: 'opposite',
        length_ft: 5000,
        width_ft: 60,
        surface: test_data[:source]
      )
    end

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    surface_tests.each do |le_ident, test_data|
      runway = AirportRunway.find_by(airport_id: airport.id, le_ident: le_ident)
      assert_equal test_data[:expected], runway.surface,
                   "Expected '#{test_data[:source]}' to normalise to '#{test_data[:expected]}'"
    end
  end

  test 'combine_sources handles unknown surface types' do
    airport = create_test_airport

    create_runway_source(
      le_ident: '99L',
      he_ident: '17R',
      length_ft: 5000,
      width_ft: 60,
      surface: 'UNUSUAL_SURFACE_TYPE'
    )

    batch = Processors::Runway::Runway.combine_sources
    batch.apply!(by: nil)

    runway = AirportRunway.find_by(airport_id: airport.id, le_ident: '99L')
    assert_equal 'unknown', runway.surface, 'Expected unknown surface to be normalised'
  end
end
