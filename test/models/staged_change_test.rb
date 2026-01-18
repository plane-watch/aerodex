# frozen_string_literal: true

require "test_helper"

class StagedChangeTest < ActiveSupport::TestCase
  setup do
    @batch = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :processing
    )
  end

  test "valid with required attributes" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create,
      diff: { "registration" => [nil, "VH-ABC"] }
    )
    assert change.valid?
  end

  test "invalid without staged_batch" do
    change = StagedChange.new(
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:staged_batch], "must exist"
  end

  test "invalid without record_type" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_identifier: "7C1469",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:record_type], "can't be blank"
  end

  test "invalid without record_identifier" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:record_identifier], "can't be blank"
  end

  test "record_id is optional for creates" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create,
      record_id: nil
    )
    assert change.valid?
  end

  test "diff defaults to empty hash" do
    change = StagedChange.new
    assert_equal({}, change.diff)
  end

  test "creates scope returns only create operations" do
    create_change = StagedChange.create!(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create
    )
    update_change = StagedChange.create!(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1470",
      record_id: 123,
      operation: :update
    )

    results = StagedChange.creates
    assert_includes results, create_change
    assert_not_includes results, update_change
  end
end
