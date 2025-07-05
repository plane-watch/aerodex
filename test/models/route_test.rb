# == Schema Information
#
# Table name: routes
#
#  id          :integer          not null, primary key
#  call_sign   :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          not null
#
# Indexes
#
#  index_routes_on_operator_id  (operator_id)
#

require "test_helper"

class RouteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
