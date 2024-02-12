# == Schema Information
#
# Table name: operators
#
#  id         :bigint           not null, primary key
#  country    :string
#  iata_code  :string
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class OperatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
