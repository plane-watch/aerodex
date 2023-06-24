class FlightInformationRegion < ApplicationRecord
  has_many :airports
  has_many :airport_runways, through: :airports

end
