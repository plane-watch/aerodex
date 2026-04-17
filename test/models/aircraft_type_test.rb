# == Schema Information
#
# Table name: aircraft_types
#
#  id               :integer          not null, primary key
#  manufacturer_id  :integer
#  type_code        :string
#  name             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  category         :integer
#  wtc              :string
#  engines          :integer
#  engine_type      :string
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  aircraft_count   :integer          default("0"), not null
#
# Indexes
#
#  index_aircraft_types_on_manufacturer_id     (manufacturer_id)
#  index_aircraft_types_on_type_code_and_name  (type_code,name) UNIQUE
#

require 'test_helper'

class AircraftTypeTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
