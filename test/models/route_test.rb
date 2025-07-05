# == Schema Information
#
# Table name: routes
#
#  id          :bigint           not null, primary key
#  call_sign   :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :bigint           not null
#
# Indexes
#
#  index_routes_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#
require "test_helper"

class RouteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
