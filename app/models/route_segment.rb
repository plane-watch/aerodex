class RouteSegment < ApplicationRecord
  belongs_to :route
  belongs_to :airport
  has_one :flight_information_region, through: :airport
  has_one :operator, through: :route

end
