# frozen_string_literal: true

require 'test_helper'

class Admin::StagedBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  # Access control tests
  test 'index redirects non-admin users' do
    sign_in @non_admin
    get admin_staged_batches_path
    assert_redirected_to root_path
  end

  test 'index accessible to admin users' do
    sign_in @admin
    get admin_staged_batches_path
    assert_response :success
  end

  # Index tests
  test 'index lists staged batches' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )

    get admin_staged_batches_path
    assert_response :success
    assert_select 'table tbody tr', minimum: 1
  end

  test 'index filters by status' do
    sign_in @admin
    pending_batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )
    applied_batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :applied
    )

    get admin_staged_batches_path(status: 'pending')
    assert_response :success
  end

  test 'index filters by entity_type' do
    sign_in @admin
    get admin_staged_batches_path(entity_type: 'Aircraft')
    assert_response :success
  end

  # Apply tests
  test 'apply enqueues job and redirects' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Country::Country',
      entity_type: 'Country',
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: 'Country',
      record_identifier: 'CT',
      operation: :create,
      diff: {
        'name' => [nil, 'Controller Test'],
        'iso_2char_code' => [nil, 'CT'],
        'iso_3char_code' => [nil, 'CTT']
      }
    )

    assert_enqueued_with(job: ApplyBatchJob) do
      post apply_admin_staged_batch_path(batch)
    end

    batch.reload
    assert_equal 'applying', batch.status
    assert_redirected_to admin_staged_batch_path(batch)
  end

  test 'apply rejects non-pending batch' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :applied
    )

    post apply_admin_staged_batch_path(batch)

    assert_redirected_to admin_staged_batch_path(batch)
    assert_equal 'Batch is not pending', flash[:alert]
  end

  # Reject tests
  test 'reject action rejects pending batch' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )

    post reject_admin_staged_batch_path(batch), params: { reason: 'Data looks incorrect' }
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal 'rejected', batch.status
    assert_equal 'Data looks incorrect', batch.notes
  end

  test 'reject action without reason still works' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )

    post reject_admin_staged_batch_path(batch)
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal 'rejected', batch.status
  end

  # Show tests
  test 'show displays batch details' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: 'Test',
      record_identifier: 'TEST-1',
      operation: :create,
      diff: { 'name' => [nil, 'Test'] }
    )

    get admin_staged_batch_path(batch)
    assert_response :success
    assert_select 'h3', 'Batch Details'
  end

  test 'show filters changes by search' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: 'Test',
      record_identifier: 'VH-ABC',
      operation: :create,
      diff: { 'name' => [nil, 'Test'] }
    )
    batch.staged_changes.create!(
      record_type: 'Test',
      record_identifier: 'N12345',
      operation: :create,
      diff: { 'name' => [nil, 'Other'] }
    )

    get admin_staged_batch_path(batch, search: 'VH')
    assert_response :success
    assert_match 'VH-ABC', response.body
    assert_no_match(/N12345/, response.body)
  end

  test 'show filters changes by operation' do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: 'Processors::Test::Test',
      entity_type: 'Test',
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: 'Test',
      record_identifier: 'CREATE-1',
      operation: :create,
      diff: { 'name' => [nil, 'New Record'] }
    )
    batch.staged_changes.create!(
      record_type: 'Test',
      record_identifier: 'UPDATE-1',
      operation: :update,
      diff: { 'name' => ['Old Name', 'New Name'] }
    )

    get admin_staged_batch_path(batch, operation: 'create')
    assert_response :success
    assert_match 'CREATE-1', response.body
    assert_no_match(/UPDATE-1/, response.body)
  end
end
