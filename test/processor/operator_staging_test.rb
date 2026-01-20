# frozen_string_literal: true

require "test_helper"

class OperatorStagingTest < ActiveSupport::TestCase
  setup do
    # Clear any existing staged batches
    StagedBatch.destroy_all

    # Clear existing operators and operator sources
    Operator.delete_all
    Source::Operator::VRSDataOperatorSource.delete_all
    Source::Operator::OpenTravelOperatorSource.delete_all

    # Create test source records
    @vrs_source = Source::Operator::VRSDataOperatorSource.create!(
      name: "Test Airline",
      icao_code: "TST",
      iata_code: "TS",
      data: {},
      import_date: Time.current
    )
  end

  test "combine_sources creates a staged batch" do
    assert_difference "StagedBatch.count", 1 do
      Processors::Operator::Operator.combine_sources
    end
  end

  test "combine_sources does not create operators directly" do
    assert_no_difference "Operator.count" do
      Processors::Operator::Operator.combine_sources
    end
  end

  test "combine_sources creates staged changes" do
    batch = Processors::Operator::Operator.combine_sources

    assert batch.staged_changes.any?
    assert_equal "Operator", batch.staged_changes.first.record_type
  end

  test "apply! creates the operators" do
    batch = Processors::Operator::Operator.combine_sources

    assert_difference "Operator.count", 1 do
      batch.apply!(by: nil)
    end

    operator = Operator.find_by(icao_code: "TST")
    assert_equal "Test Airline", operator.name
  end

  test "staged batch has correct summary" do
    batch = Processors::Operator::Operator.combine_sources

    assert_equal 1, batch.summary["created"]
    assert_equal 0, batch.summary["updated"]
  end

  test "staged batch has pending status" do
    batch = Processors::Operator::Operator.combine_sources

    assert_equal "pending", batch.status
  end

  test "staged batch has correct entity type" do
    batch = Processors::Operator::Operator.combine_sources

    assert_equal "Operator", batch.entity_type
  end

  test "combine_sources with multiple sources creates correct staged changes" do
    # Add an OTD source with matching ICAO code
    Source::Operator::OpenTravelOperatorSource.create!(
      name: "TEST AIRLINE",
      icao_code: "TST",
      iata_code: "TS",
      data: {},
      import_date: Time.current
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should be 1 staged change (merged from both sources)
    assert_equal 1, batch.staged_changes.count
    assert_equal "create", batch.staged_changes.first.operation
  end

  test "combine_sources with unmatched OTD creates separate staged change" do
    # Add an OTD source that does not match VRS
    Source::Operator::OpenTravelOperatorSource.create!(
      name: "Another Airline",
      icao_code: "ANO",
      iata_code: "AN",
      data: {},
      import_date: Time.current
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should be 2 staged changes: one for TST (VRS), one for ANO (OTD)
    assert_equal 2, batch.staged_changes.count
    assert_equal 2, batch.summary["created"]
  end

  test "combine_sources stages updates for existing operators" do
    # Create an existing operator
    existing = Operator.create!(
      name: "Old Test Airline",
      icao_code: "TST",
      iata_code: "TS"
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should stage an update, not a create
    assert_equal 1, batch.staged_changes.count
    change = batch.staged_changes.first
    assert_equal "update", change.operation
    assert_equal existing.id, change.record_id
    assert_equal 0, batch.summary["created"]
    assert_equal 1, batch.summary["updated"]
  end

  test "apply! updates existing operators" do
    # Create an existing operator
    existing = Operator.create!(
      name: "Old Test Airline",
      icao_code: "TST",
      iata_code: "TS"
    )

    batch = Processors::Operator::Operator.combine_sources

    assert_no_difference "Operator.count" do
      batch.apply!(by: nil)
    end

    existing.reload
    assert_equal "Test Airline", existing.name
  end

  test "combine_sources does not allow concurrent pending batches" do
    Processors::Operator::Operator.combine_sources

    assert_raises RuntimeError do
      Processors::Operator::Operator.combine_sources
    end
  end
end
