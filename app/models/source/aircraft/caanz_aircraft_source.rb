# == Schema Information
#
# Table name: aircraft_sources
#
#  id                        :integer          not null, primary key
#  created_at                :datetime         not null
#  data                      :jsonb            default("{}"), not null
#  engine_count              :integer
#  engine_model              :string
#  excluded                  :boolean          default(FALSE), not null
#  excluded_at               :datetime
#  excluded_by               :string
#  exclusion_reason          :string
#  icao                      :string           not null
#  import_date               :datetime         not null
#  manufacture_year          :integer
#  manufacturer_code         :string
#  model                     :string
#  operator_icao             :string
#  operator_name             :string
#  owner                     :string
#  registration              :string           not null
#  registration_country_code :string
#  registration_date         :date
#  serial_number             :string
#  status                    :string
#  type                      :string           not null
#  type_code                 :string
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_aircraft_sources_on_data           (data)
#  index_aircraft_sources_on_excluded       (excluded)
#  index_aircraft_sources_on_icao           (icao)
#  index_aircraft_sources_on_icao_and_type  (icao,type) UNIQUE
#  index_aircraft_sources_on_registration   (registration)
#  index_aircraft_sources_on_type           (type)
#

# frozen_string_literal: true

module Source
  module Aircraft
    # Source records for aircraft from CAANZ (Civil Aviation Authority of New Zealand).
    #
    # CAANZ is the New Zealand government authority responsible for aircraft registration.
    # This source is considered highly reliable for New Zealand-registered aircraft (ZK-XXX).
    class CAANZAircraftSource < AircraftSource
      # Default country code for CAANZ registrations
      COUNTRY_CODE = 'NZ'

      before_validation :set_default_country

      private

      def set_default_country
        self.registration_country_code ||= COUNTRY_CODE
      end
    end
  end
end
