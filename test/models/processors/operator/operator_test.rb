# frozen_string_literal: true

require 'test_helper'

class Processors::Operator::OperatorTest < ActiveSupport::TestCase
  # Test ICAO codes that won't conflict with real data
  TEST_ICAO_CODES = %w[ZAY ZTS ZDP].freeze

  setup do
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clear operator sources
    Source::Operator::VRSDataOperatorSource.delete_all
    Source::Operator::OpenTravelOperatorSource.delete_all
    Source::Operator::AirlineCodesOperatorSource.delete_all

    # Clean up test operators
    Operator.where(icao_code: TEST_ICAO_CODES).delete_all

    SourceTrustScore.clear_cache!
  end

  teardown do
    Operator.where(icao_code: TEST_ICAO_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # Duplicate ICAO code handling (the "AYD" scenario)
  # ---------------------------------------------------------------------------

  test 'combine_sources does not create duplicates for same ICAO with different names' do
    # This reproduces the bug where VRS "Aladia Airlines" and OTD "AB Aviation"
    # both have ICAO "AYD" but different names, resulting in two CREATE operations.

    # Create VRS source with one name
    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: 'ZAY',
      name: 'Aladia Airlines',
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    # Create OTD source with SAME ICAO but DIFFERENT name
    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: 'ZAY',
      iata_code: 'Y6',
      name: 'AB Aviation',
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should be 1 CREATE + 1 UPDATE, not 2 CREATEs
    creates = batch.staged_changes.creates.count
    updates = batch.staged_changes.updates.count

    assert_equal 1, creates, 'Expected exactly 1 CREATE for ICAO ZAY'
    assert updates <= 1, 'Expected at most 1 UPDATE for ICAO ZAY'

    # All staged changes should reference the same ICAO
    icao_identifiers = batch.staged_changes.pluck(:record_identifier)
    assert icao_identifiers.all? { |id| id == 'ZAY' },
           "Expected all changes to reference ZAY, got: #{icao_identifiers.inspect}"
  end

  test 'combine_sources correctly merges sources with same ICAO and similar names' do
    # When names are similar enough to match, they should merge cleanly
    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: 'ZTS',
      name: 'Test Airways',
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: 'ZTS',
      name: 'Test Airways', # Same name
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should merge into single CREATE
    assert_equal 1, batch.staged_changes.creates.count
    assert_equal 0, batch.staged_changes.updates.count
  end

  test 'combine_sources finds staged operator in phase 2' do
    # VRS + OTD with same ICAO but different names
    # Phase 1 processes VRS, Phase 2 should find staged record for OTD

    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: 'ZDP',
      name: 'First Name',
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: 'ZDP',
      name: 'Second Name',
      import_date: Time.current,
      data: { 'source' => 'test' }
    )

    batch = Processors::Operator::Operator.combine_sources

    # Verify we don't have duplicate CREATEs
    create_count = batch.staged_changes.creates.count
    assert_equal 1, create_count, "Expected 1 CREATE, got #{create_count}"
  end
end
