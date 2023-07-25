class Airport < ApplicationRecord
  belongs_to :flight_information_region, optional: true
  has_many :airport_runways

  has_paper_trail

end
