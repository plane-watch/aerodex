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

require "test_helper"

class FlightInformationRegionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
