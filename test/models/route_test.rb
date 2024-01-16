# == Schema Information
#
# Table name: routes
#
#  id          :bigint           not null, primary key
#  call_sign   :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :string
#
require "test_helper"

class RouteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
