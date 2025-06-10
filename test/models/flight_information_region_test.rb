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
#  country_id :bigint           not null
#
# Indexes
#
#  index_flight_information_regions_on_country_id  (country_id)
#
# Foreign Keys
#
#  fk_rails_...  (country_id => countries.id)
#
require "test_helper"

class FlightInformationRegionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
