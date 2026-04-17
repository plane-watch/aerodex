# == Schema Information
#
# Table name: airports
#
#  id                           :integer          not null, primary key
#  airport_runways_count        :integer          default(0), not null
#  altitude                     :decimal(, )
#  city                         :string
#  country                      :string
#  country_id                   :integer          not null
#  created_at                   :datetime         not null
#  field_provenance             :jsonb            default("{}"), not null
#  flight_information_region_id :integer
#  iata_code                    :string
#  icao_code                    :string
#  last_combined_at             :datetime
#  latitude                     :decimal(9, 6)
#  longitude                    :decimal(9, 6)
#  name                         :string
#  timezone                     :string
#  updated_at                   :datetime         not null
#  wmo_code                     :string
#
# Indexes
#
#  index_airports_on_country_id  (country_id)
#

require "test_helper"

class AirportTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
