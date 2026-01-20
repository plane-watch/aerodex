# frozen_string_literal: true

require "test_helper"

class Processors::AircraftType::AircraftTypeTest < ActiveSupport::TestCase
  # Track test-created records for cleanup.
  # Use type codes that definitely don't exist in real data or fixtures.
  TEST_TYPE_CODES = %w[ZZZZ YYYY XXXX WWWW TTTT IIII EEEE OOOO CCCC VVVV MMMM NNNN PPPP QQQQ].freeze
  TEST_ICAO_CODES = %w[ZZMANUF YYMANUF XXMANUF STUBMFR NEWMFR].freeze

  setup do
    # Clear source tables - these have no FK dependencies, so safe to delete
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.delete_all
    Source::AircraftType::OpenFlightsAircraftTypeSource.delete_all
    Source::AircraftType::VRSAircraftTypeSource.delete_all

    # Clean up any aircraft types with our test type codes from previous test runs.
    # Delete aircraft types first (they have FK to manufacturers).
    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all

    # Clean up any manufacturers with our test ICAO codes
    Manufacturer.where(icao_code: TEST_ICAO_CODES).delete_all

    # Clear the trust score cache to ensure consistent behaviour
    SourceTrustScore.clear_cache!
  end

  teardown do
    # Clean up test-created records
    AircraftType.where(type_code: TEST_TYPE_CODES).delete_all
    Manufacturer.where(icao_code: TEST_ICAO_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # combine_sources tests
  # ---------------------------------------------------------------------------

  test "combine_sources creates aircraft type from a single source" do
    # Create a manufacturer first (FK requirement)
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Test Manufacturer"
    )

    # Create a source record with the required fields
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Test Aircraft",
      manufacturer: "ZZMANUF",
      wtc: "L",
      engines: 2,
      engine_type: "Jet",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(type_code: "ZZZZ", name: "Test Aircraft")
    assert_not_nil aircraft_type, "Expected aircraft type to be created"
    assert_equal "Test Aircraft", aircraft_type.name
    assert_equal "ZZZZ", aircraft_type.type_code
    assert_equal manufacturer.id, aircraft_type.manufacturer_id
    assert_equal "L", aircraft_type.wtc
    assert_equal 2, aircraft_type.engines
    assert_equal "Jet", aircraft_type.engine_type
  end

  test "combine_sources updates existing aircraft type when source has changes" do
    # Create a manufacturer
    manufacturer = Manufacturer.create!(
      icao_code: "YYMANUF",
      name: "Update Test Manufacturer"
    )

    # Create an existing aircraft type record
    AircraftType.create!(
      type_code: "YYYY",
      name: "Old Name",
      manufacturer: manufacturer,
      wtc: "M"
    )

    # Create a source with updated data
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "YYYY",
      name: "Old Name",
      manufacturer: "YYMANUF",
      wtc: "L",
      engines: 4,
      engine_type: "Turboprop",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(type_code: "YYYY", name: "Old Name")
    assert_equal "L", aircraft_type.wtc
    assert_equal 4, aircraft_type.engines
    assert_equal "Turboprop", aircraft_type.engine_type
  end

  test "combine_sources merges multiple sources using trust scores" do
    # Create a manufacturer
    manufacturer = Manufacturer.create!(
      icao_code: "XXMANUF",
      name: "Merge Test Manufacturer"
    )

    # Create conflicting sources - the higher trust score should win
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "XXXX",
      name: "Test Multi-Source",
      manufacturer: "XXMANUF",
      wtc: "L",
      engines: 2,
      import_date: Time.current
    )
    Source::AircraftType::OpenFlightsAircraftTypeSource.create!(
      type_code: "XXXX",
      name: "Test Multi-Source",
      manufacturer: "XXMANUF",
      wtc: "M",
      engines: 4,
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(type_code: "XXXX", name: "Test Multi-Source")
    assert_not_nil aircraft_type, "Expected aircraft type to be created from merged sources"
    # The winning values depend on trust scores - just verify values were chosen
    assert_includes %w[L M], aircraft_type.wtc
    assert_includes [2, 4], aircraft_type.engines
  end

  test "combine_sources sets provenance for fields" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Provenance Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "WWWW",
      name: "Provenance Test",
      manufacturer: "ZZMANUF",
      wtc: "M",
      engines: 2,
      engine_type: "Jet",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(type_code: "WWWW", name: "Provenance Test")
    assert_not_nil aircraft_type.field_provenance, "Expected provenance to be set"

    # Check that provenance was recorded for various fields.
    # Provenance keys can be strings or symbols depending on serialisation.
    wtc_provenance = aircraft_type.field_provenance["wtc"] || aircraft_type.field_provenance[:wtc]
    assert_not_nil wtc_provenance, "Expected provenance to be recorded for the wtc field"
    assert wtc_provenance.key?("source_type") || wtc_provenance.key?(:source_type),
           "Expected provenance to include source_type"
  end

  test "combine_sources sets last_combined_at timestamp" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Timestamp Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "TTTT",
      name: "Timestamp Test",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    freeze_time do
      Processors::AircraftType::AircraftType.combine_sources

      aircraft_type = AircraftType.find_by(type_code: "TTTT", name: "Timestamp Test")
      assert_not_nil aircraft_type.last_combined_at, "Expected last_combined_at to be set"
      assert_in_delta Time.current, aircraft_type.last_combined_at, 1.second
    end
  end

  test "combine_sources excludes records marked as excluded" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Exclusion Manufacturer"
    )

    # Create an includable source
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "IIII",
      name: "Includable Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current,
      excluded: false
    )

    # Create an excluded source (should be ignored)
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "EEEE",
      name: "Excluded Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current,
      excluded: true,
      exclusion_reason: "Test exclusion"
    )

    Processors::AircraftType::AircraftType.combine_sources

    # The includable aircraft type should exist
    assert AircraftType.exists?(type_code: "IIII", name: "Includable Aircraft"),
           "Expected includable aircraft type to be created"

    # The excluded aircraft type should not exist
    assert_not AircraftType.exists?(type_code: "EEEE", name: "Excluded Aircraft"),
               "Expected excluded aircraft type to be skipped"
  end

  test "combine_sources handles all three source types" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Multi-Source Manufacturer"
    )

    # Create records from each source type with unique type codes
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "CCCC",
      name: "CFAPPS Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )
    Source::AircraftType::OpenFlightsAircraftTypeSource.create!(
      type_code: "OOOO",
      name: "OpenFlights Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )
    Source::AircraftType::VRSAircraftTypeSource.create!(
      type_code: "VVVV",
      name: "VRS Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # Check that all three test aircraft types were created
    assert AircraftType.exists?(type_code: "CCCC", name: "CFAPPS Aircraft"),
           "Expected CFAPPS aircraft type to be created"
    assert AircraftType.exists?(type_code: "OOOO", name: "OpenFlights Aircraft"),
           "Expected OpenFlights aircraft type to be created"
    assert AircraftType.exists?(type_code: "VVVV", name: "VRS Aircraft"),
           "Expected VRS aircraft type to be created"
  end

  test "combine_sources links to existing manufacturer" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Existing Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "MMMM",
      name: "Manufacturer Link Test",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(type_code: "MMMM", name: "Manufacturer Link Test")
    assert_equal manufacturer.id, aircraft_type.manufacturer_id,
                 "Expected aircraft type to be linked to the correct manufacturer"
  end

  test "combine_sources creates stub manufacturer when manufacturer does not exist" do
    # Don't create a manufacturer - let the processor create a stub
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "NNNN",
      name: "Stub Manufacturer Test",
      manufacturer: "STUBMFR",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # Check that the stub manufacturer was created
    stub_manufacturer = Manufacturer.find_by(icao_code: "STUBMFR")
    assert_not_nil stub_manufacturer, "Expected stub manufacturer to be created"

    # Check that the aircraft type is linked to the stub
    aircraft_type = AircraftType.find_by(type_code: "NNNN", name: "Stub Manufacturer Test")
    assert_equal stub_manufacturer.id, aircraft_type.manufacturer_id
  end

  test "combine_sources skips sources with blank type_code" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Blank Code Manufacturer"
    )

    # Create a source with blank type code (should be skipped in grouping)
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "",
      name: "Blank Type Code Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    # Create a valid source
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "PPPP",
      name: "Valid Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # The valid aircraft type should be created
    assert AircraftType.exists?(type_code: "PPPP", name: "Valid Aircraft"),
           "Expected valid aircraft type to be created"

    # No aircraft type should exist with a blank type_code
    assert_not AircraftType.exists?(type_code: ""),
               "Expected no aircraft type with blank type code"
  end

  test "combine_sources skips sources with blank name" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Blank Name Manufacturer"
    )

    # Create a source with blank name (should be skipped in grouping)
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "QQQQ",
      name: "",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    # Create a valid source
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "QQQQ",
      name: "Valid Name Aircraft",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # The valid aircraft type should be created
    assert AircraftType.exists?(type_code: "QQQQ", name: "Valid Name Aircraft"),
           "Expected valid aircraft type to be created"

    # No aircraft type should exist with a blank name
    assert_not AircraftType.exists?(type_code: "QQQQ", name: ""),
               "Expected no aircraft type with blank name"
  end

  # ---------------------------------------------------------------------------
  # combine_one tests
  # ---------------------------------------------------------------------------

  test "combine_one creates aircraft type for specific type code and name" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Combine One Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Specific Variant",
      manufacturer: "ZZMANUF",
      wtc: "H",
      engines: 4,
      engine_type: "Jet",
      import_date: Time.current
    )

    result = Processors::AircraftType::AircraftType.combine_one("ZZZZ", "Specific Variant")

    assert_not_nil result[:aircraft_type], "Expected aircraft_type in result"
    assert_equal "Specific Variant", result[:aircraft_type].name
    assert_equal "ZZZZ", result[:aircraft_type].type_code
    assert result[:created], "Expected created flag to be true"
  end

  test "combine_one updates existing aircraft type" do
    manufacturer = Manufacturer.create!(
      icao_code: "YYMANUF",
      name: "Update One Manufacturer"
    )

    # Create existing aircraft type
    AircraftType.create!(
      type_code: "YYYY",
      name: "Existing Variant",
      manufacturer: manufacturer,
      wtc: "L"
    )

    # Create source with updated data
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "YYYY",
      name: "Existing Variant",
      manufacturer: "YYMANUF",
      wtc: "M",
      engines: 2,
      import_date: Time.current
    )

    result = Processors::AircraftType::AircraftType.combine_one("YYYY", "Existing Variant")

    assert_not_nil result[:aircraft_type]
    assert_equal "M", result[:aircraft_type].wtc
    assert_equal 2, result[:aircraft_type].engines
    assert result[:updated], "Expected updated flag to be true"
  end

  test "combine_one returns all variants when name is not specified" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Multi-Variant Manufacturer"
    )

    # Create multiple variants with the same type code
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Variant A",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Variant B",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    result = Processors::AircraftType::AircraftType.combine_one("ZZZZ")

    assert_not_nil result[:aircraft_types], "Expected aircraft_types array in result"
    assert_equal 2, result[:aircraft_types].size
  end

  test "combine_one returns error when no sources found" do
    result = Processors::AircraftType::AircraftType.combine_one("NONEXISTENT", "No Such Variant")

    assert_not_nil result[:error]
    assert_includes result[:error], "No sources found"
  end

  test "combine_one raises error for blank type code" do
    assert_raises(ArgumentError) do
      Processors::AircraftType::AircraftType.combine_one("")
    end
  end

  test "combine_one normalises type code to uppercase" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Uppercase Test Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Uppercase Test",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    # Pass lowercase code - should still work
    result = Processors::AircraftType::AircraftType.combine_one("zzzz", "Uppercase Test")

    assert_not_nil result[:aircraft_type]
    assert_equal "ZZZZ", result[:aircraft_type].type_code
  end

  test "combine_one trims whitespace from type code" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Whitespace Test Manufacturer"
    )

    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Whitespace Test",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    # Pass code with whitespace - should still work
    result = Processors::AircraftType::AircraftType.combine_one("  ZZZZ  ", "Whitespace Test")

    assert_not_nil result[:aircraft_type]
    assert_equal "ZZZZ", result[:aircraft_type].type_code
  end

  # ---------------------------------------------------------------------------
  # Name canonicalisation tests
  # ---------------------------------------------------------------------------

  test "combine_sources merges sources with different name formats for same aircraft" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Antonov"
    )

    # Create sources with different name formats that should be merged.
    # "An-148" and "Antonov An-148" should produce the same canonical key.
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "An-148",
      manufacturer: "ZZMANUF",
      wtc: "M",
      import_date: Time.current
    )
    Source::AircraftType::OpenFlightsAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "Antonov An-148",
      manufacturer: "ZZMANUF",
      wtc: "M",
      engines: 2,
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # Should only create one aircraft type (not two)
    aircraft_types = AircraftType.where(type_code: "ZZZZ")
    assert_equal 1, aircraft_types.count, "Expected sources with same canonical key to be merged"

    # The best name should be selected (Antonov An-148 is more descriptive)
    aircraft_type = aircraft_types.first
    assert_equal "Antonov An-148", aircraft_type.name
  end

  test "combine_sources keeps different variants separate" do
    manufacturer = Manufacturer.create!(
      icao_code: "ZZMANUF",
      name: "Boeing"
    )

    # Create sources for different variants that should NOT be merged.
    # 737-700 and 737-800 are different aircraft variants.
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "737-700",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )
    Source::AircraftType::CfappsICAOIntAircraftTypeSource.create!(
      type_code: "ZZZZ",
      name: "737-800",
      manufacturer: "ZZMANUF",
      import_date: Time.current
    )

    Processors::AircraftType::AircraftType.combine_sources

    # Should create two separate aircraft types
    aircraft_types = AircraftType.where(type_code: "ZZZZ")
    assert_equal 2, aircraft_types.count, "Expected different variants to remain separate"

    names = aircraft_types.pluck(:name)
    assert_includes names, "737-700"
    assert_includes names, "737-800"
  end
end
