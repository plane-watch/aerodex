# == Schema Information
#
# Table name: flight_information_regions
#
#  id         :bigint           not null, primary key
#  bounds     :polygon
#  country    :string
#  icao_code  :string
#  region     :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class FlightInformationRegion < ApplicationRecord
  has_many :airports
  has_many :airport_runways, through: :airports

  has_paper_trail

end
