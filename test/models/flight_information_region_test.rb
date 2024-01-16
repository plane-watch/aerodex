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
require "test_helper"

class FlightInformationRegionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
