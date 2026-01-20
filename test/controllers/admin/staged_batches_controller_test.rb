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
end
