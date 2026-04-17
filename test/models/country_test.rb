# == Schema Information
#
# Table name: countries
#
#  id               :integer          not null, primary key
#  airports_count   :integer          default(0), not null
#  capital          :string
#  created_at       :datetime         not null
#  field_provenance :jsonb            default("{}"), not null
#  iso_2char_code   :string
#  iso_3char_code   :string
#  iso_num_code     :string
#  last_combined_at :datetime
#  name             :string
#  operators_count  :integer          default(0), not null
#  updated_at       :datetime         not null
#

require "test_helper"

class CountryTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
