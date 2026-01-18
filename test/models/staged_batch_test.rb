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

  test "apply! raises error if not pending" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :processing
    )

    assert_raises(StagedBatch::InvalidStatusError) do
      batch.apply!(by: nil)
    end
  end

  test "apply! transitions status to applied" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :pending
    )

    batch.apply!(by: nil)

    assert_equal "applied", batch.status
    assert_not_nil batch.applied_at
  end

  test "apply! creates records for create operations" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "ZZ",
      operation: :create,
      diff: {
        "name" => [nil, "Test Country"],
        "iso_2char_code" => [nil, "ZZ"],
        "iso_3char_code" => [nil, "ZZZ"]
      }
    )

    assert_difference "Country.count", 1 do
      batch.apply!(by: nil)
    end

    country = Country.find_by(iso_2char_code: "ZZ")
    assert_equal "Test Country", country.name
  end

  test "apply! updates records for update operations" do
    country = Country.create!(
      name: "Old Name",
      iso_2char_code: "YY",
      iso_3char_code: "YYY"
    )
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "YY",
      record_id: country.id,
      operation: :update,
      diff: { "name" => ["Old Name", "New Name"] }
    )

    batch.apply!(by: nil)

    country.reload
    assert_equal "New Name", country.name
  end

  test "apply! raises StaleDataError if record modified since batch created" do
    country = Country.create!(
      name: "Original",
      iso_2char_code: "XX",
      iso_3char_code: "XXX"
    )
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending,
      created_at: 1.hour.ago
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "XX",
      record_id: country.id,
      operation: :update,
      diff: { "name" => ["Original", "Staged Change"] }
    )

    # Modify the record after batch was created
    country.update!(name: "External Change")

    assert_raises(StagedBatch::StaleDataError) do
      batch.apply!(by: nil)
    end
  end
end
