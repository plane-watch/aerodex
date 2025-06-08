# frozen_string_literal: true

require 'test_helper'
require_relative '../../../app/processors/base/processor'

class Processors::Base::ProcessorTest < ActiveSupport::TestCase
  test 'processor can be loaded' do
    assert Processors::Base::Processor
  end

  test 'processor has expected methods' do
    assert_respond_to Processors::Base::Processor, :transform_field
    assert_respond_to Processors::Base::Processor, :get_source_from_url
    assert_respond_to Processors::Base::Processor, :new_import_report
  end
end 