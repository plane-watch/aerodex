# == Schema Information
#
# Table name: operators
#
#  id         :bigint           not null, primary key
#  iata_code  :string
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :bigint
#
# Indexes
#
#  index_operators_on_country_id  (country_id)
#
# Foreign Keys
#
#  fk_rails_...  (country_id => countries.id)
#
require "test_helper"

class OperatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
