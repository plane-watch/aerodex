# == Schema Information
#
# Table name: airports
#
#  id                           :bigint           not null, primary key
#  altitude                     :decimal(, )
#  city                         :string
#  country                      :string
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
require "test_helper"

class AirportTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
