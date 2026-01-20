# frozen_string_literal: true

require "test_helper"

class Admin::ProcessorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  test "index redirects non-admin users" do
    sign_in @non_admin
    get admin_processors_path
    assert_redirected_to root_path
  end

  test "index accessible to admin users" do
    sign_in @admin
    get admin_processors_path
    assert_response :success
  end

  test "index lists available processors" do
    sign_in @admin
    get admin_processors_path
    assert_response :success
    # Should list at least Aircraft, Operator processors
    assert_select "table tbody tr", minimum: 1
  end

  test "create enqueues processor job" do
    sign_in @admin

    assert_enqueued_with(job: ProcessorJob) do
      post admin_processors_path, params: { entity_type: "Country" }
    end

    assert_redirected_to admin_processors_path
    follow_redirect!
    assert_match(/enqueued/, flash[:notice])
  end

  test "create rejects invalid processor type" do
    sign_in @admin

    post admin_processors_path, params: { entity_type: "InvalidType" }
    assert_redirected_to admin_processors_path
    assert_match(/Unknown processor/, flash[:alert])
  end
end
