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
#  country_id                   :bigint           not null
#  flight_information_region_id :integer
#
# Indexes
#
#  index_airports_on_country_id  (country_id)
#
# Foreign Keys
#
#  fk_rails_...  (country_id => countries.id)
#
require "test_helper"

class AirportTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
