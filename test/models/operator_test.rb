# == Schema Information
#
# Table name: operators
#
#  id         :integer          not null, primary key
#  name       :string
#  icao_code  :string
#  iata_code  :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :integer
#
# Indexes
#
#  index_operators_on_country_id  (country_id)
#

require "test_helper"

class OperatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
