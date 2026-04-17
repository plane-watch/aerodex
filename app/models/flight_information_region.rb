# == Schema Information
#
# Table name: flight_information_regions
#
#  id         :integer          not null, primary key
#  bounds     :polygon
#  country_id :integer          not null
#  created_at :datetime         not null
#  icao_code  :string
#  region     :string
#  updated_at :datetime         not null
#
# Indexes
#
#  index_flight_information_regions_on_country_id  (country_id)
#

class FlightInformationRegion < ApplicationRecord
  include MeiliSearch::Rails
  belongs_to :country
  has_many :airports
  has_many :airport_runways, through: :airports

  has_paper_trail
end
