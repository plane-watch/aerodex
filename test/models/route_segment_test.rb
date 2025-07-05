# == Schema Information
#
# Table name: route_segments
#
#  id             :integer          not null, primary key
#  route_id       :integer
#  airport_id     :integer
#  order          :integer
#  arrival_time   :time
#  departing_time :time
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_route_segments_on_airport_id  (airport_id)
#  index_route_segments_on_route_id    (route_id)
#

require "test_helper"

class RouteSegmentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
