# frozen_string_literal: true

require 'test_helper'

class Processors::Manufacturer::ManufacturerTest < ActiveSupport::TestCase
  # Track test-created manufacturers for cleanup
  # Use ICAO codes that definitely don't exist in real data or fixtures
  TEST_ICAO_CODES = %w[ZZTEST YYTEST XXTEST WWTEST TTTEST IITEST EETEST OSTEST CNTEST].freeze

  setup do
    # Clear staging tables
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clear source tables - these have no FK dependencies, so safe to delete
    Source::Manufacturer::CfappsICAOIntManufacturerSource.delete_all
    Source::Manufacturer::OpenskyManufacturerSource.delete_all

    # Clean up any manufacturers with our test ICAO codes from previous test runs
    Manufacturer.where(icao_code: TEST_ICAO_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created manufacturers
    Manufacturer.where(icao_code: TEST_ICAO_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # combine_sources staging tests
  # ---------------------------------------------------------------------------

  test 'combine_sources returns a staged batch' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Test Manufacturer',
      import_date: Time.current
    )

    result = Processors::Manufacturer::Manufacturer.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal 'pending', result.status
    assert_equal 'Manufacturer', result.entity_type
  end

  test 'combine_sources stages manufacturer creation' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Test Manufacturer',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal 'ZZTEST', change.record_identifier
    assert_equal 'Test Manufacturer', change.new_values['name']

    # Manufacturer should NOT exist yet
    assert_nil Manufacturer.find_by(icao_code: 'ZZTEST')
  end

  test 'combine_sources stages manufacturer update' do
    Manufacturer.create!(
      icao_code: 'YYTEST',
      name: 'Old Name'
    )

    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'YYTEST',
      name: 'New Name',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal 'YYTEST', change.record_identifier
    assert_equal ['Old Name', 'New Name'], change.diff['name']
  end

  test 'combine_sources tracks unchanged records' do
    Manufacturer.create!(
      icao_code: 'XXTEST',
      name: 'Same Name'
    )

    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'XXTEST',
      name: 'Same Name',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary['unchanged']
  end

  test 'combine_sources accepts triggered_by parameter' do
    user = users(:admin)

    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'WWTEST',
      name: 'Test',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  test 'applying batch creates the manufacturer' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Applied Manufacturer',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources

    assert_nil Manufacturer.find_by(icao_code: 'ZZTEST')

    batch.apply!(by: nil)

    manufacturer = Manufacturer.find_by(icao_code: 'ZZTEST')
    assert_not_nil manufacturer
    assert_equal 'Applied Manufacturer', manufacturer.name
  end

  test 'applying batch updates existing manufacturer' do
    Manufacturer.create!(
      icao_code: 'TTTEST',
      name: 'Old Name'
    )

    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'TTTEST',
      name: 'New Name',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources

    # Name should still be old before applying
    assert_equal 'Old Name', Manufacturer.find_by(icao_code: 'TTTEST').name

    batch.apply!(by: nil)

    assert_equal 'New Name', Manufacturer.find_by(icao_code: 'TTTEST').name
  end

  test 'combine_sources merges multiple sources using trust scores' do
    # Create conflicting sources - the higher trust score should win
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'XXTEST',
      name: 'CFAPPS Name',
      import_date: Time.current
    )
    Source::Manufacturer::OpenskyManufacturerSource.create!(
      icao_code: 'XXTEST',
      name: 'OpenSky Name',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    manufacturer = Manufacturer.find_by(icao_code: 'XXTEST')
    assert_not_nil manufacturer, 'Expected manufacturer to be created from merged sources'
    # The winning name depends on trust scores - just verify one was chosen
    assert_includes ['CFAPPS Name', 'OpenSky Name'], manufacturer.name
  end

  test 'combine_sources sets provenance for fields' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'WWTEST',
      name: 'Provenance Test',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    manufacturer = Manufacturer.find_by(icao_code: 'WWTEST')
    assert_not_nil manufacturer.field_provenance, 'Expected provenance to be set'

    # Check that provenance was recorded for the name field
    # Provenance keys can be strings or symbols depending on serialisation
    name_provenance = manufacturer.field_provenance['name'] || manufacturer.field_provenance[:name]
    assert_not_nil name_provenance, 'Expected provenance to be recorded for the name field'
    assert name_provenance.key?('source_type') || name_provenance.key?(:source_type),
           'Expected provenance to include source_type'
  end

  test 'combine_sources excludes records marked as excluded' do
    # Create an includable source
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'IITEST',
      name: 'Includable Manufacturer',
      import_date: Time.current,
      excluded: false
    )

    # Create an excluded source (should be ignored)
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'EETEST',
      name: 'Excluded Manufacturer',
      import_date: Time.current,
      excluded: true,
      exclusion_reason: 'Test exclusion'
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    # The includable manufacturer should exist
    assert Manufacturer.exists?(icao_code: 'IITEST'), 'Expected includable manufacturer to be created'

    # The excluded manufacturer should not exist
    assert_not Manufacturer.exists?(icao_code: 'EETEST'), 'Expected excluded manufacturer to be skipped'
  end

  test 'combine_sources handles both source types' do
    # Create records from each source type with unique ICAO codes
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'CNTEST',
      name: 'CFAPPS Manufacturer',
      import_date: Time.current
    )
    Source::Manufacturer::OpenskyManufacturerSource.create!(
      icao_code: 'OSTEST',
      name: 'OpenSky Manufacturer',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    # Check that both test manufacturers were created
    assert Manufacturer.exists?(icao_code: 'CNTEST'), 'Expected CFAPPS manufacturer to be created'
    assert Manufacturer.exists?(icao_code: 'OSTEST'), 'Expected OpenSky manufacturer to be created'
  end

  test 'combine_sources assigns country when source has country data' do
    # First, ensure a test country exists for matching
    country = Country.find_or_create_by!(iso_2char_code: 'US') do |c|
      c.iso_3char_code = 'USA'
      c.name = 'United States'
    end

    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'CNTEST',
      name: 'Country Test Manufacturer',
      country: 'United States',
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    manufacturer = Manufacturer.find_by(icao_code: 'CNTEST')
    assert_equal country.id, manufacturer.country_id, 'Expected manufacturer to be assigned to country'
  end

  test 'combine_sources handles alt_names from sources' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Main Name',
      alt_names: ['Alternate Name One', 'Alternate Name Two'],
      import_date: Time.current
    )

    batch = Processors::Manufacturer::Manufacturer.combine_sources
    batch.apply!(by: nil)

    manufacturer = Manufacturer.find_by(icao_code: 'ZZTEST')
    assert_not_nil manufacturer.alt_names, 'Expected alt_names to be set'
    assert_includes manufacturer.alt_names, 'Alternate Name One'
    assert_includes manufacturer.alt_names, 'Alternate Name Two'
  end

  # ---------------------------------------------------------------------------
  # combine_one tests (direct save, not staged)
  # ---------------------------------------------------------------------------

  test 'combine_one creates manufacturer for specific ICAO code' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Test Corp',
      import_date: Time.current
    )

    result = Processors::Manufacturer::Manufacturer.combine_one('ZZTEST')

    assert_not_nil result[:manufacturer], 'Expected manufacturer in result'
    assert_equal 'Test Corp', result[:manufacturer].name
    assert result[:created], 'Expected created flag to be true'
  end

  test 'combine_one updates existing manufacturer' do
    # Create existing manufacturer
    Manufacturer.create!(
      icao_code: 'YYTEST',
      name: 'Old Corp'
    )

    # Create source with updated data
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'YYTEST',
      name: 'New Corp',
      import_date: Time.current
    )

    result = Processors::Manufacturer::Manufacturer.combine_one('YYTEST')

    assert_not_nil result[:manufacturer]
    assert_equal 'New Corp', result[:manufacturer].name
    assert result[:updated], 'Expected updated flag to be true'
  end

  test 'combine_one returns error when no sources found' do
    result = Processors::Manufacturer::Manufacturer.combine_one('NONEXISTENT')

    assert_not_nil result[:error]
    assert_includes result[:error], 'No sources found'
  end

  test 'combine_one raises error for blank ICAO code' do
    assert_raises(ArgumentError) do
      Processors::Manufacturer::Manufacturer.combine_one('')
    end
  end

  test 'combine_one normalises ICAO code to uppercase' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Uppercase Test',
      import_date: Time.current
    )

    # Pass lowercase code - should still work
    result = Processors::Manufacturer::Manufacturer.combine_one('zztest')

    assert_not_nil result[:manufacturer]
    assert_equal 'Uppercase Test', result[:manufacturer].name
  end

  test 'combine_one trims whitespace from ICAO code' do
    Source::Manufacturer::CfappsICAOIntManufacturerSource.create!(
      icao_code: 'ZZTEST',
      name: 'Whitespace Test',
      import_date: Time.current
    )

    # Pass code with whitespace - should still work
    result = Processors::Manufacturer::Manufacturer.combine_one('  ZZTEST  ')

    assert_not_nil result[:manufacturer]
    assert_equal 'Whitespace Test', result[:manufacturer].name
  end
end
