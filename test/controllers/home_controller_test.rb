require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  # test "the truth" do
  #   assert true
  # end
end

class HomeControllerDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test 'dashboard loads successfully with pending batches' do
    sign_in @user

    # Create a pending batch
    batch = StagedBatch.create!(
      processor_type: 'TestProcessor',
      entity_type: 'Test',
      status: :pending,
      summary: { 'created' => 5, 'updated' => 3, 'unchanged' => 0 }
    )

    get dashboard_path

    assert_response :success
    # Verify the dashboard page structure loads correctly
    assert_select 'h3', /Pending Approvals/
  ensure
    batch&.destroy
  end

  test 'dashboard does not error when no pending batches exist' do
    sign_in @user

    # Ensure no pending batches exist
    StagedBatch.pending.destroy_all

    get dashboard_path

    assert_response :success
    assert_select 'h3', /Pending Approvals/
  end
end
