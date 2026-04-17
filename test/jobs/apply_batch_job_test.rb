# frozen_string_literal: true

require "test_helper"

class ApplyBatchJobTest < ActiveJob::TestCase
  test "perform applies the batch" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :applying,
      apply_progress: 0,
      apply_total: 1
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "JJ",
      operation: :create,
      diff: {
        "name" => [nil, "Job Test Country"],
        "iso_2char_code" => [nil, "JJ"],
        "iso_3char_code" => [nil, "JJJ"]
      }
    )

    ApplyBatchJob.perform_now(batch.id, user_id: nil)

    batch.reload
    assert_equal "applied", batch.status
    assert_not_nil Country.find_by(iso_2char_code: "JJ")
  end

  test "perform marks batch as failed on error" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :applying
    )
    # Create an update operation for a non-existent record to trigger an error
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "NONEXISTENT",
      record_id: 999_999_999,
      operation: :update,
      diff: {
        "name" => ["Old Name", "New Name"]
      }
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      ApplyBatchJob.perform_now(batch.id, user_id: nil)
    end

    batch.reload
    assert_equal "failed", batch.status
    assert_includes batch.error_message, "RecordNotFound"
  end
end
