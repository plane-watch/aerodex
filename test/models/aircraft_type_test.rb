# == Schema Information
#
# Table name: aircraft_types
#
#  id              :integer          not null, primary key
#  manufacturer_id :integer
#  type_code       :string
#  name            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  category        :integer
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
