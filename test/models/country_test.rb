# == Schema Information
#
# Table name: countries
#
#  id             :integer          not null, primary key
#  iso_2char_code :string
#  iso_3char_code :string
#  iso_num_code   :string
#  name           :string
#  capital        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

require "test_helper"

class CountryTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
