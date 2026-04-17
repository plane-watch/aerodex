# == Schema Information
#
# Table name: airport_runways
#
#  id               :integer          not null, primary key
#  airport_id       :integer
#  closed           :boolean          default(FALSE)
#  created_at       :datetime         not null
#  field_provenance :jsonb            default("{}"), not null
#  he_ident         :string
#  heading          :decimal(, )
#  last_combined_at :datetime
#  le_ident         :string
#  length           :decimal(, )
#  lighted          :boolean          default(FALSE)
#  runway_name      :string
#  surface          :string
#  updated_at       :datetime         not null
#  width            :decimal(, )
#

require "test_helper"

class AirportRunwayTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
