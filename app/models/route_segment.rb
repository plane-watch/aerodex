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
# Indexes
#
#  index_route_segments_on_airport_id  (airport_id)
#  index_route_segments_on_route_id    (route_id)
#
class RouteSegment < ApplicationRecord
  include MeiliSearch::Rails

  belongs_to :route
  belongs_to :airport
  has_one :flight_information_region, through: :airport
  has_one :operator, through: :route

  has_paper_trail
end
