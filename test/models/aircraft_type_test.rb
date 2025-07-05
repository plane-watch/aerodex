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
# Indexes
#
#  index_aircraft_types_on_manufacturer_id  (manufacturer_id)
#
require 'test_helper'

class AircraftTypeTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
