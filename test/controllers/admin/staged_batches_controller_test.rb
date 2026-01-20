# frozen_string_literal: true

require "test_helper"

class Admin::StagedBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  # Access control tests
  test "index redirects non-admin users" do
    sign_in @non_admin
    get admin_staged_batches_path
    assert_redirected_to root_path
  end

  test "index accessible to admin users" do
    sign_in @admin
    get admin_staged_batches_path
    assert_response :success
  end

  # Index tests
  test "index lists staged batches" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    get admin_staged_batches_path
    assert_response :success
    assert_select "table tbody tr", minimum: 1
  end

  test "index filters by status" do
    sign_in @admin
    pending_batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )
    applied_batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :applied
    )

    get admin_staged_batches_path(status: "pending")
    assert_response :success
  end

  test "index filters by entity_type" do
    sign_in @admin
    get admin_staged_batches_path(entity_type: "Aircraft")
    assert_response :success
  end

  # Apply tests
  test "apply action applies pending batch" do
    sign_in @admin
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
      post apply_admin_staged_batch_path(batch)
    end

    assert_redirected_to admin_staged_batch_path(batch)
    batch.reload
    assert_equal "applied", batch.status
  end

  test "apply action shows error for non-pending batch" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :applied
    )

    post apply_admin_staged_batch_path(batch)
    assert_redirected_to admin_staged_batch_path(batch)
    follow_redirect!
    assert_match(/Failed to apply/, flash[:alert])
  end

  # Reject tests
  test "reject action rejects pending batch" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    post reject_admin_staged_batch_path(batch), params: { reason: "Data looks incorrect" }
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
    assert_equal "Data looks incorrect", batch.notes
  end

  test "reject action without reason still works" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    post reject_admin_staged_batch_path(batch)
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
  end
end
