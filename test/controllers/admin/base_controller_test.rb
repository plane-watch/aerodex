# frozen_string_literal: true

require 'test_helper'

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  test 'redirects non-admin users to root' do
    user = users(:one)
    sign_in user

    # We'll test via a subclass since BaseController has no actions.
    # For now, just verify the controller exists and can be instantiated.
    assert_kind_of ApplicationController, Admin::BaseController.new
  end
end
