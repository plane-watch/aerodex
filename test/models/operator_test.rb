# == Schema Information
#
# Table name: operators
#
#  id               :integer          not null, primary key
#  name             :string
#  country          :string
#  icao_code        :string
#  iata_code        :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  country_id       :integer
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  aircraft_count   :integer          default(0), not null
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
