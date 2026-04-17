# == Schema Information
#
# Table name: aircraft
#
#  id                      :integer          not null, primary key
#  aircraft_name           :string
#  aircraft_type_id        :integer
#  cabin_configuration     :string
#  created_at              :datetime         not null
#  engine_count            :integer
#  engine_model            :string
#  field_provenance        :jsonb            default("{}"), not null
#  icao                    :string
#  last_combined_at        :datetime
#  manufacture_year        :integer
#  model                   :string
#  operator_id             :integer
#  owner                   :string
#  registration            :string
#  registration_country_id :integer          not null
#  registration_date       :date
#  serial_number           :string
#  status                  :integer          default(0)
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_aircraft_on_aircraft_type_id         (aircraft_type_id)
#  index_aircraft_on_operator_id              (operator_id)
#  index_aircraft_on_registration_country_id  (registration_country_id)
#

require "test_helper"

class AircraftTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
