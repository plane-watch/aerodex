# frozen_string_literal: true

require "test_helper"

class StagedBatchTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    batch = StagedBatch.new(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft"
    )
    assert batch.valid?
  end

  test "invalid without processor_type" do
    batch = StagedBatch.new(entity_type: "Aircraft")
    assert_not batch.valid?
    assert_includes batch.errors[:processor_type], "can't be blank"
  end

  test "invalid without entity_type" do
    batch = StagedBatch.new(processor_type: "Processors::Aircraft::Aircraft")
    assert_not batch.valid?
    assert_includes batch.errors[:entity_type], "can't be blank"
  end

  test "default status is processing" do
    batch = StagedBatch.new
    assert_equal "processing", batch.status
  end

  test "pending scope returns only pending batches" do
    processing = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :processing
    )
    pending = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :pending
    )
    applied = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :applied
    )

    results = StagedBatch.pending
    assert_includes results, pending
    assert_not_includes results, processing
    assert_not_includes results, applied
  end

  test "for_entity scope filters by entity type" do
    aircraft_batch = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft"
    )
    operator_batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator"
    )

    results = StagedBatch.for_entity("Aircraft")
    assert_includes results, aircraft_batch
    assert_not_includes results, operator_batch
  end

  test "summary defaults to empty hash" do
    batch = StagedBatch.new
    assert_equal({}, batch.summary)
  end
end
