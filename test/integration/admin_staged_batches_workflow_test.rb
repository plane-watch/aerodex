# frozen_string_literal: true

require "test_helper"

class AdminStagedBatchesWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
  end

  test "full workflow: trigger processor, review batch, apply changes" do
    sign_in @admin

    # 1. View processors page
    get admin_processors_path
    assert_response :success

    # 2. Trigger a processor (Country is small and safe for tests)
    # Note: This enqueues a job, doesn't run it synchronously
    assert_enqueued_with(job: ProcessorJob) do
      post admin_processors_path, params: { entity_type: "Country" }
    end
    assert_redirected_to admin_processors_path

    # 3. Create a batch manually for testing the review flow
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending,
      summary: { "created" => 1, "updated" => 0 }
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

    # 4. View staged batches index
    get admin_staged_batches_path
    assert_response :success
    assert_select "tr", text: /Country/

    # 5. View batch details
    get admin_staged_batch_path(batch)
    assert_response :success
    assert_select "h3", "Batch Details"

    # 6. Apply the batch
    assert_difference "Country.count", 1 do
      post apply_admin_staged_batch_path(batch)
    end
    assert_redirected_to admin_staged_batch_path(batch)

    # 7. Verify batch status changed
    batch.reload
    assert_equal "applied", batch.status
    assert_equal @admin, batch.reviewed_by

    # 8. Verify the country was created
    country = Country.find_by(iso_2char_code: "ZZ")
    assert_not_nil country
    assert_equal "Test Country", country.name
  end

  test "reject workflow: review batch and reject with reason" do
    sign_in @admin

    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "YY",
      operation: :create,
      diff: { "name" => [nil, "Bad Data"] }
    )

    # Reject the batch
    post reject_admin_staged_batch_path(batch), params: { reason: "Data quality issue" }
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
    assert_equal "Data quality issue", batch.notes
    assert_equal @admin, batch.reviewed_by
  end
end
