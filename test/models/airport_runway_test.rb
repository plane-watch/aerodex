# == Schema Information
#
# Table name: airport_runways
#
#  id          :integer          not null, primary key
#  airport_id  :integer
#  runway_name :string
#  heading     :decimal(, )
#  length      :decimal(, )
#  width       :decimal(, )
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

require "test_helper"

class AirportRunwayTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
