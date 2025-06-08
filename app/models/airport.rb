# == Schema Information
#
# Table name: airports
#
#  id                           :bigint           not null, primary key
#  altitude                     :decimal(, )
#  city                         :string
#  country                      :id
#  iata_code                    :string
#  icao_code                    :string
#  latitude                     :decimal(9, 6)
#  longitude                    :decimal(9, 6)
#  name                         :string
#  timezone                     :string
#  wmo_code                     :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  flight_information_region_id :integer
#
class Airport < ApplicationRecord
  belongs_to :flight_information_region, optional: true
  has_many :airport_runways
  belongs_to :country, optional: true

  has_paper_trail

end
