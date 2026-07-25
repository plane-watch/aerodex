# frozen_string_literal: true

require 'test_helper'

class Processors::Aircraft::AircraftTest < ActiveSupport::TestCase
  # Track test-created records for cleanup.
  # Use identifiers that definitely don't exist in real data or fixtures.
  TEST_ICAO_CODES = %w[FFFFFF EEEEEE DDDDDD CCCCCC BBBBBB AAAAAA].freeze
  TEST_COUNTRY_CODES = %w[ZZ YY].freeze
  TEST_OPERATOR_NAMES = ['Test Operator ZZ', 'Test Operator YY', 'Auto Created Operator ZZ'].freeze
  TEST_TYPE_CODES = %w[ZZZZ YYYY].freeze
  TEST_MANUFACTURER_NAMES = ['Test Manufacturer ZZ', 'Test Manufacturer YY'].freeze

  setup do
    # Clear staging tables first
    StagedChange.delete_all
    StagedBatch.delete_all

    # Clear test-created records from previous runs (in FK-safe order)
    Aircraft.where(icao: TEST_ICAO_CODES).delete_all

    # Clear operators by name (since test operators don't have ICAO codes)
    Operator.where(name: TEST_OPERATOR_NAMES).delete_all

    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all
    Manufacturer.where(name: TEST_MANUFACTURER_NAMES).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all

    # Clear source tables for our test ICAO codes
    Source::Aircraft::CASAAircraftSource.where(icao: TEST_ICAO_CODES).delete_all
    Source::Aircraft::CAANZAircraftSource.where(icao: TEST_ICAO_CODES).delete_all
    if defined?(Source::Aircraft::VRSAircraftSource)
      Source::Aircraft::VRSAircraftSource.where(icao: TEST_ICAO_CODES).delete_all
    end
    if defined?(Source::Aircraft::OpenskyAircraftSource)
      Source::Aircraft::OpenskyAircraftSource.where(icao: TEST_ICAO_CODES).delete_all
    end

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created records in reverse FK order
    Aircraft.where(icao: TEST_ICAO_CODES).delete_all
    Operator.where(name: TEST_OPERATOR_NAMES).delete_all
    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all
    Manufacturer.where(name: TEST_MANUFACTURER_NAMES).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # Helper methods
  # ---------------------------------------------------------------------------

  # Creates a test country for aircraft tests
  def create_test_country(code: 'ZZ')
    Country.find_or_create_by!(iso_2char_code: code) do |c|
      c.iso_3char_code = "#{code}Z"
      c.name = "Test Country #{code}"
    end
  end

  # Creates a test manufacturer
  def create_test_manufacturer(name: 'Test Manufacturer ZZ')
    Manufacturer.find_or_create_by!(name: name)
  end

  # Creates a test aircraft type
  def create_test_aircraft_type(type_code: 'ZZZZ', model: 'Test Model', manufacturer: nil)
    manufacturer ||= create_test_manufacturer
    AircraftType.find_or_create_by!(type_code: type_code) do |at|
      at.name = model
      at.manufacturer = manufacturer
    end
  end

  # Creates a test operator
  def create_test_operator(name: 'Test Operator ZZ', icao_code: nil, country: nil)
    country ||= create_test_country
    Operator.find_or_create_by!(name: name) do |op|
      op.icao_code = icao_code
      op.country = country
    end
  end

  # Creates a CASA aircraft source record with required fields
  def create_casa_source(icao:, registration: 'VH-TST', **attrs)
    # Ensure the aircraft type exists if type_code is provided
    type_code = attrs[:type_code] || 'ZZZZ'
    create_test_aircraft_type(type_code: type_code) unless AircraftType.exists?(type_code: type_code)

    defaults = {
      serial_number: "SN#{icao}",
      owner: 'Test Owner',
      operator_name: 'Test Operator ZZ',
      type_code: type_code
    }
    Source::Aircraft::CASAAircraftSource.create!(
      icao: icao,
      registration: registration,
      import_date: Time.current,
      **defaults.merge(attrs)
    )
  end

  # Creates a test aircraft with all required fields
  def create_test_aircraft(icao:, registration:, country: nil, operator: nil, aircraft_type: nil)
    country ||= create_test_country
    operator ||= create_test_operator
    aircraft_type ||= create_test_aircraft_type

    Aircraft.create!(
      icao: icao,
      registration: registration,
      registration_country: country,
      operator: operator,
      aircraft_type: aircraft_type,
      serial_number: "SN#{icao}",
      owner: 'Test Owner'
    )
  end

  # ---------------------------------------------------------------------------
  # combine_sources staging tests
  # ---------------------------------------------------------------------------

  test 'combine_sources returns a staged batch' do
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-AAA', operator_name: operator.name)

    result = Processors::Aircraft::Aircraft.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal 'pending', result.status
    assert_equal 'Aircraft', result.entity_type
  end

  test 'combine_sources stages aircraft creation' do
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-BBB', model: 'Test Aircraft', operator_name: operator.name)

    batch = Processors::Aircraft::Aircraft.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal 'FFFFFF', change.record_identifier
    assert_equal 'VH-BBB', change.new_values['registration']

    # Aircraft should NOT exist yet
    assert_nil Aircraft.find_by(icao: 'FFFFFF')
  end

  test 'combine_sources stages aircraft update' do
    # Create existing aircraft with all required fields
    operator = create_test_operator
    create_test_aircraft(icao: 'EEEEEE', registration: 'VH-OLD', operator: operator)

    # Create source with updated data (use same operator to avoid creating stub)
    create_casa_source(icao: 'EEEEEE', registration: 'VH-NEW', operator_name: operator.name)

    batch = Processors::Aircraft::Aircraft.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal 'EEEEEE', change.record_identifier
    assert_equal %w[VH-OLD VH-NEW], change.diff['registration']

    # Aircraft should still have old registration
    assert_equal 'VH-OLD', Aircraft.find_by(icao: 'EEEEEE').registration
  end

  test 'combine_sources tracks unchanged records' do
    # CASA sources default to AU, so use the same country for the aircraft
    australia = Country.find_or_create_by!(iso_2char_code: 'AU') do |c|
      c.iso_3char_code = 'AUS'
      c.name = 'Australia'
    end
    operator = create_test_operator
    aircraft_type = create_test_aircraft_type

    aircraft = Aircraft.create!(
      icao: 'DDDDDD',
      registration: 'VH-SAM',
      registration_country: australia,
      operator: operator,
      aircraft_type: aircraft_type,
      serial_number: 'SNDDDDDD',
      owner: 'Test Owner'
    )

    # Create source with same data (use same operator, serial, owner, type_code)
    create_casa_source(
      icao: 'DDDDDD',
      registration: 'VH-SAM',
      operator_name: operator.name,
      serial_number: aircraft.serial_number,
      owner: aircraft.owner,
      type_code: aircraft_type.type_code
    )

    batch = Processors::Aircraft::Aircraft.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary['unchanged']
  end

  test 'combine_sources accepts triggered_by parameter' do
    user = users(:admin)
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-TRG', operator_name: operator.name)

    batch = Processors::Aircraft::Aircraft.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  test 'applying batch creates the aircraft' do
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-APP', model: 'Applied Model', operator_name: operator.name)

    batch = Processors::Aircraft::Aircraft.combine_sources

    assert_nil Aircraft.find_by(icao: 'FFFFFF')
    assert batch.staged_changes.creates.count > 0, 'Expected staged changes to create aircraft'

    batch.apply!(by: nil)

    aircraft = Aircraft.find_by(icao: 'FFFFFF')
    assert_not_nil aircraft
    assert_equal 'VH-APP', aircraft.registration
  end

  test 'applying batch updates existing aircraft' do
    operator = create_test_operator
    create_test_aircraft(icao: 'CCCCCC', registration: 'VH-OLD', operator: operator)

    create_casa_source(icao: 'CCCCCC', registration: 'VH-UPD', operator_name: operator.name)

    batch = Processors::Aircraft::Aircraft.combine_sources

    # Registration should still be old before applying
    assert_equal 'VH-OLD', Aircraft.find_by(icao: 'CCCCCC').registration
    assert batch.staged_changes.updates.count > 0, 'Expected staged changes to update aircraft'

    batch.apply!(by: nil)

    assert_equal 'VH-UPD', Aircraft.find_by(icao: 'CCCCCC').registration
  end

  # ---------------------------------------------------------------------------
  # Stub operator creation tests
  # ---------------------------------------------------------------------------

  test 'combine_sources creates stub operators batch when operators are auto-created' do
    # Create a country for the source (CASA defaults to AU)
    Country.find_or_create_by!(iso_2char_code: 'AU') do |c|
      c.iso_3char_code = 'AUS'
      c.name = 'Australia'
    end

    # Create a source with an operator name that doesn't exist
    create_casa_source(
      icao: 'BBBBBB',
      registration: 'VH-ZZZ',
      operator_name: 'Auto Created Operator ZZ'
    )

    Processors::Aircraft::Aircraft.combine_sources

    # Check that a stub operators batch was created
    stub_batch = StagedBatch.where(entity_type: 'Operator', status: 'applied').last
    assert_not_nil stub_batch, 'Expected stub operators batch to be created'
    assert_equal 'applied', stub_batch.status

    # Check that the operator was actually created
    operator = Operator.find_by(name: 'Auto Created Operator ZZ')
    assert_not_nil operator, 'Expected operator to be created'

    # Check that the stub batch has a staged change for the operator
    assert_equal 1, stub_batch.staged_changes.count
    change = stub_batch.staged_changes.first
    assert_equal 'Operator', change.record_type
    assert_equal operator.id, change.record_id
  end

  test 'combine_sources does not create stub batch when no operators auto-created' do
    # Create an operator that already exists
    create_test_operator(name: 'Test Operator ZZ')

    # Create source referencing the existing operator
    create_casa_source(
      icao: 'AAAAAA',
      registration: 'VH-EXI',
      operator_name: 'Test Operator ZZ'
    )

    initial_batch_count = StagedBatch.count
    Processors::Aircraft::Aircraft.combine_sources

    # Only the aircraft batch should be created, not a stub operators batch
    operator_batches = StagedBatch.where(entity_type: 'Operator')
    assert_equal 0, operator_batches.count, 'Expected no stub operators batch when operators already exist'
  end

  test 'combine_sources links aircraft to existing operator' do
    operator = create_test_operator(name: 'Test Operator YY')

    create_casa_source(
      icao: 'FFFFFF',
      registration: 'VH-LNK',
      operator_name: 'Test Operator YY'
    )

    batch = Processors::Aircraft::Aircraft.combine_sources
    assert batch.staged_changes.creates.count > 0, 'Expected staged changes to create aircraft'

    batch.apply!(by: nil)

    aircraft = Aircraft.find_by(icao: 'FFFFFF')
    assert_equal operator.id, aircraft.operator_id
  end

  # ---------------------------------------------------------------------------
  # combine_one tests (direct save, not staged)
  # ---------------------------------------------------------------------------

  test 'combine_one creates aircraft for specific ICAO' do
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-ONE', model: 'Single Test', operator_name: operator.name)

    result = Processors::Aircraft::Aircraft.combine_one('FFFFFF')

    assert_not_nil result[:aircraft], 'Expected aircraft in result'
    assert_equal 'VH-ONE', result[:aircraft].registration
    assert result[:created], 'Expected created flag to be true'
  end

  test 'combine_one updates existing aircraft' do
    operator = create_test_operator
    create_test_aircraft(icao: 'EEEEEE', registration: 'VH-EXS', operator: operator)

    create_casa_source(icao: 'EEEEEE', registration: 'VH-UPD', model: 'Updated Model', operator_name: operator.name)

    result = Processors::Aircraft::Aircraft.combine_one('EEEEEE')

    assert_not_nil result[:aircraft]
    assert_equal 'VH-UPD', result[:aircraft].registration
    assert result[:updated], 'Expected updated flag to be true'
  end

  test 'combine_one returns error when no sources found' do
    result = Processors::Aircraft::Aircraft.combine_one('ZZZZZZ')

    assert_not_nil result[:error]
    assert_includes result[:error], 'No sources found'
  end

  test 'combine_one raises error for blank ICAO' do
    assert_raises(ArgumentError) do
      Processors::Aircraft::Aircraft.combine_one('')
    end
  end

  test 'combine_one normalises ICAO to uppercase' do
    operator = create_test_operator
    create_casa_source(icao: 'FFFFFF', registration: 'VH-NRM', operator_name: operator.name)

    # Pass lowercase ICAO - should still work
    result = Processors::Aircraft::Aircraft.combine_one('ffffff')

    assert_not_nil result[:aircraft]
    assert_equal 'VH-NRM', result[:aircraft].registration
  end
end
