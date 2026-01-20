# frozen_string_literal: true

require "test_helper"

class Processors::Aircraft::AircraftTest < ActiveSupport::TestCase
  # Track test-created records for cleanup.
  # Use identifiers that definitely don't exist in real data or fixtures.
  TEST_ICAO_CODES = %w[FFFFFF EEEEEE DDDDDD].freeze
  TEST_COUNTRY_CODES = %w[ZZ YY].freeze
  TEST_OPERATOR_ICAOS = %w[ZZZ YYY].freeze
  TEST_TYPE_CODES = %w[ZZZZ YYYY].freeze
  TEST_MANUFACTURER_NAMES = ["Test Manufacturer ZZ", "Test Manufacturer YY"].freeze

  setup do
    # Clear test-created records from previous runs (in FK-safe order)
    Aircraft.where(icao: TEST_ICAO_CODES).delete_all
    Operator.where(icao_code: TEST_OPERATOR_ICAOS).delete_all
    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all
    Manufacturer.where(name: TEST_MANUFACTURER_NAMES).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created records in reverse FK order
    Aircraft.where(icao: TEST_ICAO_CODES).delete_all
    Operator.where(icao_code: TEST_OPERATOR_ICAOS).delete_all
    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all
    Manufacturer.where(name: TEST_MANUFACTURER_NAMES).delete_all
    Country.where(iso_2char_code: TEST_COUNTRY_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # Helper methods
  # ---------------------------------------------------------------------------

  # Creates a test country for aircraft tests
  def create_test_country(code: "ZZ")
    Country.find_or_create_by!(iso_2char_code: code) do |c|
      c.iso_3char_code = "#{code}Z"
      c.name = "Test Country #{code}"
    end
  end

  # Creates a test manufacturer
  def create_test_manufacturer(name: "Test Manufacturer ZZ")
    Manufacturer.find_or_create_by!(name: name)
  end

  # Creates a test aircraft type
  def create_test_aircraft_type(type_code: "ZZZZ", model: "Test Model", manufacturer: nil)
    manufacturer ||= create_test_manufacturer
    AircraftType.find_or_create_by!(type_code: type_code) do |at|
      at.name = model
      at.manufacturer = manufacturer
    end
  end

  # Creates a test operator
  def create_test_operator(name: "Test Operator", icao_code: "ZZZ", country: nil)
    country ||= create_test_country
    Operator.find_or_create_by!(icao_code: icao_code) do |op|
      op.name = name
      op.country = country
    end
  end

  # ---------------------------------------------------------------------------
  # Baseline tests
  # ---------------------------------------------------------------------------
  # Note: The Aircraft processor is the most complex processor in the system
  # with multiple FKs and large datasets. These placeholder tests document
  # expected behaviour; full tests will be written during the staging migration.

  test "combine_sources creates aircraft from sources" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end

  test "combine_sources updates existing aircraft" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end

  test "combine_sources links to operator and aircraft type" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end
end
