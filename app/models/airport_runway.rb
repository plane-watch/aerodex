class AirportRunway < ApplicationRecord
  belongs_to :airport
  has_one :flight_information_region, through: :airport
end
