# == Schema Information
#
# Table name: airports
#
#  id                           :integer          not null, primary key
#  name                         :string
#  city                         :string
#  country                      :string
#  iata_code                    :string
#  icao_code                    :string
#  wmo_code                     :string
#  flight_information_region_id :integer
#  latitude                     :decimal(9, 6)
#  longitude                    :decimal(9, 6)
#  altitude                     :decimal(, )
#  timezone                     :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  country_id                   :integer          not null
#
# Indexes
#
#  index_airports_on_country_id  (country_id)
#

class Airport < ApplicationRecord
  belongs_to :flight_information_region, optional: true
  has_many :airport_runways
  has_many :route_segments
  belongs_to :country, optional: true

  has_paper_trail
end
