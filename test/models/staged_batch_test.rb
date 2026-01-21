# == Schema Information
#
# Table name: staged_batches
#
#  id             :uuid             not null, primary key
#  processor_type :string           not null
#  entity_type    :string           not null
#  status         :integer          default(0), not null
#  summary        :jsonb            default("{}"), not null
#  created_by_id  :integer
#  reviewed_by_id :integer
#  job_id         :string
#  started_at     :datetime
#  completed_at   :datetime
#  applied_at     :datetime
#  reviewed_at    :datetime
#  notes          :text
#  error_message  :text
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  apply_progress :integer          default(0)
#  apply_total    :integer
#
# Indexes
#
#  index_staged_batches_on_created_at      (created_at)
#  index_staged_batches_on_created_by_id   (created_by_id)
#  index_staged_batches_on_entity_type     (entity_type)
#  index_staged_batches_on_job_id          (job_id)
#  index_staged_batches_on_reviewed_by_id  (reviewed_by_id)
#  index_staged_batches_on_status          (status)
#

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
    # Must have at least one change to apply
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "TEST",
      operation: :create,
      diff: {
        "name" => [nil, "Test Operator"],
        "icao_code" => [nil, "TST"]
      }
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

  test "reject! transitions status to rejected" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :pending
    )

    batch.reject!(by: nil)

    assert_equal "rejected", batch.status
    assert_not_nil batch.reviewed_at
  end

  test "reject! stores reason in notes field" do
    user = User.create!(email: "reviewer@example.com", password: "password123")
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :pending
    )

    reason = "Data looks incorrect, needs verification"
    batch.reject!(by: user, reason: reason)

    assert_equal reason, batch.notes
    assert_equal user, batch.reviewed_by
  end

  test "reject! raises error if not pending" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :applied
    )

    assert_raises(StagedBatch::InvalidStatusError) do
      batch.reject!(by: nil)
    end
  end

  test "apply! raises ApplyError for empty batch" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )

    assert_raises(StagedBatch::ApplyError) do
      batch.apply!(by: nil)
    end
  end

  test "apply! applies batch with multiple record types" do
    batch = StagedBatch.create!(
      processor_type: "Processors::MultiType::Processor",
      entity_type: "Mixed",
      status: :pending
    )

    # Add a Country create
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "AA",
      operation: :create,
      diff: {
        "name" => [nil, "Test Country A"],
        "iso_2char_code" => [nil, "AA"],
        "iso_3char_code" => [nil, "AAA"]
      }
    )

    # Add an Operator create
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "TEST-OP",
      operation: :create,
      diff: {
        "name" => [nil, "Test Operator"],
        "iata_code" => [nil, "TO"],
        "icao_code" => [nil, "TST"]
      }
    )

    assert_difference ["Country.count", "Operator.count"], 1 do
      batch.apply!(by: nil)
    end

    country = Country.find_by(iso_2char_code: "AA")
    assert_equal "Test Country A", country.name

    operator = Operator.find_by(icao_code: "TST")
    assert_equal "Test Operator", operator.name
  end

  test "apply! handles staged changes with different attribute sets" do
    # Regression test: insert_all requires all records to have the same keys.
    # Different staged changes may capture different attributes in their diffs.
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :pending
    )

    # First operator has name and icao_code
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "OP1",
      operation: :create,
      diff: {
        "name" => [nil, "Operator One"],
        "icao_code" => [nil, "OP1"]
      }
    )

    # Second operator has name, icao_code, AND iata_code (different keys)
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "OP2",
      operation: :create,
      diff: {
        "name" => [nil, "Operator Two"],
        "icao_code" => [nil, "OP2"],
        "iata_code" => [nil, "O2"]
      }
    )

    # Should not raise "All objects being inserted must have the same keys"
    assert_difference "Operator.count", 2 do
      batch.apply!(by: nil)
    end

    op1 = Operator.find_by(icao_code: "OP1")
    op2 = Operator.find_by(icao_code: "OP2")

    assert_equal "Operator One", op1.name
    assert_nil op1.iata_code

    assert_equal "Operator Two", op2.name
    assert_equal "O2", op2.iata_code
  end

  test "applying status exists" do
    batch = StagedBatch.new(
      processor_type: "Test",
      entity_type: "Test",
      status: :applying
    )
    assert batch.applying?
  end

  test "apply! rolls back transaction on stale data" do
    # Create an existing country
    country = Country.create!(
      name: "Original",
      iso_2char_code: "BB",
      iso_3char_code: "BBB"
    )

    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending,
      created_at: 1.hour.ago
    )

    # Add a create for a new country
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "CC",
      operation: :create,
      diff: {
        "name" => [nil, "New Country"],
        "iso_2char_code" => [nil, "CC"],
        "iso_3char_code" => [nil, "CCC"]
      }
    )

    # Add an update for the existing country
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "BB",
      record_id: country.id,
      operation: :update,
      diff: { "name" => ["Original", "Updated"] }
    )

    # Modify the existing country after batch was created
    country.update!(name: "External Change")

    # Attempt to apply should fail with stale data error
    assert_raises(StagedBatch::StaleDataError) do
      batch.apply!(by: nil)
    end

    # Verify no new country was created (transaction rolled back)
    assert_nil Country.find_by(iso_2char_code: "CC")

    # Verify existing country was not updated (transaction rolled back)
    country.reload
    assert_equal "External Change", country.name

    # Verify the batch status is marked as failed (error handling persists the failure)
    batch.reload
    assert_equal "failed", batch.status
    assert_includes batch.error_message, "StaleDataError"
  end

  test "apply! works when status is applying" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :applying,
      apply_progress: 0,
      apply_total: 1
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "WW",
      operation: :create,
      diff: {
        "name" => [nil, "Test Country W"],
        "iso_2char_code" => [nil, "WW"],
        "iso_3char_code" => [nil, "WWW"]
      }
    )

    batch.apply!(by: nil)

    assert_equal "applied", batch.status
  end

  test "apply! rolls back all changes on validation failure" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :applying
    )

    # First change will succeed
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "TST1",
      operation: :create,
      diff: {
        "name" => [nil, "Valid Operator"],
        "icao_code" => [nil, "TST"]
      }
    )

    # Second change will fail (missing required name field)
    batch.staged_changes.create!(
      record_type: "Operator",
      record_identifier: "TST2",
      operation: :create,
      diff: {
        "icao_code" => [nil, "TS2"]
        # Missing name - will fail validation (presence: true)
      }
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      batch.apply!(by: nil)
    end

    # First operator should NOT exist (rolled back)
    assert_nil Operator.find_by(icao_code: "TST")

    # Batch should be marked as failed
    batch.reload
    assert_equal "failed", batch.status
    assert_includes batch.error_message, "Validation failed"
  end
end
