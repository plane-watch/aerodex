# frozen_string_literal: true

# == Schema Information
#
# Table name: aircraft
#
#  id                      :integer          not null, primary key
#  icao                    :string
#  aircraft_type_id        :integer
#  serial_number           :string
#  manufacture_year        :integer
#  owner                   :string
#  operator_id             :integer
#  registration            :string
#  registration_date       :date
#  engine_count            :integer
#  engine_model            :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  cabin_configuration     :string
#  aircraft_name           :string
#  status                  :integer          default(0)
#  model                   :string
#  registration_country_id :integer          not null
#  field_provenance        :jsonb            default("{}"), not null
#  last_combined_at        :datetime
#
# Indexes
#
#  index_aircraft_on_aircraft_type_id         (aircraft_type_id)
#  index_aircraft_on_operator_id              (operator_id)
#  index_aircraft_on_registration_country_id  (registration_country_id)
#

require 'test_helper'

class AircraftTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
