# == Schema Information
#
# Table name: route_segments
#
#  id             :bigint           not null, primary key
#  arrival_time   :time
#  departing_time :time
#  order          :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  airport_id     :integer
#  route_id       :integer
#
require "test_helper"

class RouteSegmentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
