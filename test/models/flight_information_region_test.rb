# == Schema Information
#
# Table name: flight_information_regions
#
#  id         :integer          not null, primary key
#  icao_code  :string
#  country    :string
#  region     :string
#  bounds     :polygon
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :integer          not null
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
