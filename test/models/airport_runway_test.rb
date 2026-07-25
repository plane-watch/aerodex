# == Schema Information
#
# Table name: airport_runways
#
#  id               :integer          not null, primary key
#  airport_id       :integer
#  runway_name      :string
#  heading          :decimal(, )
#  length           :decimal(, )
#  width            :decimal(, )
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  le_ident         :string
#  he_ident         :string
#  surface          :string
#  lighted          :boolean          default(FALSE)
#  closed           :boolean          default(FALSE)
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#

require "test_helper"

class AirportRunwayTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
