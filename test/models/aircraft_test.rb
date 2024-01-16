# == Schema Information
#
# Table name: aircraft
#
#  id                   :bigint           not null, primary key
#  engine_count         :integer
#  engine_model         :string
#  icao                 :string
#  manufacture_year     :integer
#  owner                :string
#  registration         :string
#  registration_country :string
#  registration_date    :date
#  serial_number        :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  aircraft_type_id     :integer
#  operator_id          :integer
#
require "test_helper"

class AircraftTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
