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
class RouteSegment < ApplicationRecord
  belongs_to :route
  belongs_to :airport
  has_one :flight_information_region, through: :airport
  has_one :operator, through: :route

  has_paper_trail

end
