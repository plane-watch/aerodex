# == Schema Information
#
# Table name: aircraft_types
#
#  id              :bigint           not null, primary key
#  category        :integer
#  name            :string
#  type_code       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  manufacturer_id :integer
#
require "test_helper"

class AircraftTypeTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
