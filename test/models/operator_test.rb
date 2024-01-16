# == Schema Information
#
# Table name: operators
#
#  id                           :bigint           not null, primary key
#  charter_callsign_pattern     :string
#  country                      :string
#  iata_callsign                :string
#  icao_callsign                :string
#  name                         :string
#  positioning_callsign_pattern :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
require "test_helper"

class OperatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
