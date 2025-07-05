# frozen_string_literal: true

require 'test_helper'

class Processors::BaseTest < ActiveSupport::TestCase
  test 'base module can be loaded' do
    assert Processors::Base
  end

  test 'base module has expected methods when included' do
    test_class = Class.new do
      include Processors::Base
    end

    assert_respond_to test_class, :transform_field
    assert_respond_to test_class, :get_source_from_url
    assert_respond_to test_class, :new_import_report
  end
end 