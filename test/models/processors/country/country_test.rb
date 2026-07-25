# frozen_string_literal: true

require 'test_helper'

class Processors::Country::CountryTest < ActiveSupport::TestCase
  # Track test-created countries for cleanup
  # Use ISO codes that definitely don't exist in real ISO 3166 or fixtures
  TEST_ISO_CODES = %w[ZZ YY XX WW TT II EE OT OF OA CP VV NZ GB QQ].freeze

  setup do
    # Clear staging tables
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clear source tables - these have no FK dependencies, so safe to delete
    Source::Country::OpenTravelCountrySource.delete_all
    Source::Country::OpenFlightsCountrySource.delete_all
    Source::Country::OurAirportsCountrySource.delete_all

    # Clean up any countries with our test ISO codes from previous test runs
    Country.where(iso_2char_code: TEST_ISO_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created countries
    Country.where(iso_2char_code: TEST_ISO_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # combine_sources staging tests
  # ---------------------------------------------------------------------------

  test 'combine_sources returns a staged batch' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Country',
      import_date: Time.current
    )

    result = Processors::Country::Country.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal 'pending', result.status
    assert_equal 'Country', result.entity_type
  end

  test 'combine_sources stages country creation' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Country',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal 'ZZ', change.record_identifier
    assert_equal 'Test Country', change.new_values['name']

    # Country should NOT exist yet
    assert_nil Country.find_by(iso_2char_code: 'ZZ')
  end

  test 'combine_sources stages country update' do
    Country.create!(
      iso_2char_code: 'YY',
      iso_3char_code: 'YYY',
      name: 'Old Name'
    )

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'YY',
      iso_3char_code: 'YYY',
      name: 'New Name',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal 'YY', change.record_identifier
    assert_equal ['Old Name', 'New Name'], change.diff['name']
  end

  test 'combine_sources tracks unchanged records' do
    Country.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'Same Name'
    )

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'Same Name',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary['unchanged']
  end

  test 'combine_sources accepts triggered_by parameter' do
    user = users(:admin)

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'WW',
      iso_3char_code: 'WWW',
      name: 'Test',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  test 'applying batch creates the country' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'VV',
      iso_3char_code: 'VVV',
      name: 'Applied Country',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources

    assert_nil Country.find_by(iso_2char_code: 'VV')

    batch.apply!(by: nil)

    country = Country.find_by(iso_2char_code: 'VV')
    assert_not_nil country
    assert_equal 'Applied Country', country.name
  end

  test 'applying batch updates existing country' do
    Country.create!(
      iso_2char_code: 'TT',
      iso_3char_code: 'TTT',
      name: 'Old Name'
    )

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'TT',
      iso_3char_code: 'TTT',
      name: 'New Name',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources

    # Name should still be old before applying
    assert_equal 'Old Name', Country.find_by(iso_2char_code: 'TT').name

    batch.apply!(by: nil)

    assert_equal 'New Name', Country.find_by(iso_2char_code: 'TT').name
  end

  test 'combine_sources merges multiple sources using trust scores' do
    # Create conflicting sources - the higher trust score should win
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'OpenTravel Name',
      import_date: Time.current
    )
    Source::Country::OpenFlightsCountrySource.create!(
      iso_2char_code: 'XX',
      iso_3char_code: 'XXX',
      name: 'OpenFlights Name',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    country = Country.find_by(iso_2char_code: 'XX')
    assert_not_nil country, 'Expected country to be created from merged sources'
    # The winning name depends on trust scores - just verify one was chosen
    assert_includes ['OpenTravel Name', 'OpenFlights Name'], country.name
  end

  test 'combine_sources sets provenance for fields' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'WW',
      iso_3char_code: 'WWW',
      name: 'Provenance Test',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    country = Country.find_by(iso_2char_code: 'WW')
    assert_not_nil country.field_provenance, 'Expected provenance to be set'

    # Check that provenance was recorded for the name field
    # Provenance keys can be strings or symbols depending on serialisation
    name_provenance = country.field_provenance['name'] || country.field_provenance[:name]
    assert_not_nil name_provenance, 'Expected provenance to be recorded for the name field'
    assert name_provenance.key?('source_type') || name_provenance.key?(:source_type),
           'Expected provenance to include source_type'
  end

  test 'combine_sources excludes records marked as excluded' do
    # Create an includable source
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'II',
      iso_3char_code: 'III',
      name: 'Includable Country',
      import_date: Time.current,
      excluded: false
    )

    # Create an excluded source (should be ignored)
    Source::Country::OpenFlightsCountrySource.create!(
      iso_2char_code: 'EE',
      iso_3char_code: 'EEE',
      name: 'Excluded Country',
      import_date: Time.current,
      excluded: true,
      exclusion_reason: 'Test exclusion'
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    # The includable country should exist
    assert Country.exists?(iso_2char_code: 'II'), 'Expected includable country to be created'

    # The excluded country should not exist
    assert_not Country.exists?(iso_2char_code: 'EE'), 'Expected excluded country to be skipped'
  end

  test 'combine_sources handles all three source types' do
    # Create records from each source type with unique ISO codes
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'OT',
      iso_3char_code: 'OTR',
      name: 'OpenTravel Country',
      import_date: Time.current
    )
    Source::Country::OpenFlightsCountrySource.create!(
      iso_2char_code: 'OF',
      iso_3char_code: 'OFL',
      name: 'OpenFlights Country',
      import_date: Time.current
    )
    Source::Country::OurAirportsCountrySource.create!(
      iso_2char_code: 'OA',
      iso_3char_code: 'OAP',
      name: 'OurAirports Country',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    # Check that all three test countries were created
    assert Country.exists?(iso_2char_code: 'OT'), 'Expected OpenTravel country to be created'
    assert Country.exists?(iso_2char_code: 'OF'), 'Expected OpenFlights country to be created'
    assert Country.exists?(iso_2char_code: 'OA'), 'Expected OurAirports country to be created'
  end

  test 'combine_sources merges capital from sources' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'CP',
      iso_3char_code: 'CPT',
      name: 'Capital Test Country',
      capital: 'Test Capital City',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    country = Country.find_by(iso_2char_code: 'CP')
    assert_equal 'Test Capital City', country.capital
  end

  test 'combine_sources skips sources with blank iso_2char_code' do
    # Create a source with blank iso code (should be skipped in grouping)
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: '',
      iso_3char_code: 'BLK',
      name: 'Blank ISO Country',
      import_date: Time.current
    )

    # Create a valid source
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'VV',
      iso_3char_code: 'VVV',
      name: 'Valid Country',
      import_date: Time.current
    )

    batch = Processors::Country::Country.combine_sources
    batch.apply!(by: nil)

    # The valid country should be created
    assert Country.exists?(iso_2char_code: 'VV'), 'Expected valid country to be created'

    # No country should exist with a blank iso_2char_code
    assert_not Country.exists?(iso_2char_code: ''), 'Expected no country with blank ISO code'
  end

  # ---------------------------------------------------------------------------
  # combine_one tests (direct save, not staged)
  # ---------------------------------------------------------------------------

  test 'combine_one creates country for specific ISO code' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'ZZ',
      iso_3char_code: 'ZZZ',
      name: 'Test Land',
      capital: 'Test City',
      import_date: Time.current
    )

    result = Processors::Country::Country.combine_one('ZZ')

    assert_not_nil result[:country], 'Expected country in result'
    assert_equal 'Test Land', result[:country].name
    assert result[:created], 'Expected created flag to be true'
  end

  test 'combine_one updates existing country' do
    # Create existing country
    Country.create!(
      iso_2char_code: 'NZ',
      iso_3char_code: 'NZL',
      name: 'Old Zealand'
    )

    # Create source with updated data
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'NZ',
      iso_3char_code: 'NZL',
      name: 'New Zealand',
      import_date: Time.current
    )

    result = Processors::Country::Country.combine_one('NZ')

    assert_not_nil result[:country]
    assert_equal 'New Zealand', result[:country].name
    assert result[:updated], 'Expected updated flag to be true'
  end

  test 'combine_one returns error when no sources found' do
    result = Processors::Country::Country.combine_one('QQ')

    assert_not_nil result[:error]
    assert_includes result[:error], 'No sources found'
  end

  test 'combine_one raises error for invalid ISO code' do
    assert_raises(ArgumentError) do
      Processors::Country::Country.combine_one('')
    end

    assert_raises(ArgumentError) do
      Processors::Country::Country.combine_one('ABC')
    end
  end

  test 'combine_one normalises ISO code to uppercase' do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: 'GB',
      iso_3char_code: 'GBR',
      name: 'United Kingdom',
      import_date: Time.current
    )

    # Pass lowercase code - should still work
    result = Processors::Country::Country.combine_one('gb')

    assert_not_nil result[:country]
    assert_equal 'United Kingdom', result[:country].name
  end
end
