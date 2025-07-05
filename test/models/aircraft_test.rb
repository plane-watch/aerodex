# == Schema Information
#
# Table name: aircraft
#
#  id                      :bigint           not null, primary key
#  aircraft_name           :string
#  cabin_configuration     :string
#  engine_count            :integer
#  engine_model            :string
#  icao                    :string
#  manufacture_year        :integer
#  model                   :string
#  owner                   :string
#  registration            :string
#  registration_date       :date
#  serial_number           :string
#  status                  :integer          default("active")
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  aircraft_type_id        :integer
#  operator_id             :integer
#  registration_country_id :bigint           not null
#
# Indexes
#
#  index_aircraft_on_aircraft_type_id         (aircraft_type_id)
#  index_aircraft_on_operator_id              (operator_id)
#  index_aircraft_on_registration_country_id  (registration_country_id)
#
# Foreign Keys
#
#  fk_rails_...  (registration_country_id => countries.id)
#
require "test_helper"

class AircraftTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
