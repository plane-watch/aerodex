# == Schema Information
#
# Table name: aircraft_types
#
#  id               :integer          not null, primary key
#  aircraft_count   :integer          default(0), not null
#  category         :integer
#  created_at       :datetime         not null
#  engine_type      :string
#  engines          :integer
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  manufacturer_id  :integer
#  name             :string
#  type_code        :string
#  updated_at       :datetime         not null
#  wtc              :string
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
