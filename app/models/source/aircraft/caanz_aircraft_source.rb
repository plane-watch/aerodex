# == Schema Information
#
# Table name: aircraft_sources
#
#  id                        :integer          not null, primary key
#  type                      :string           not null
#  icao                      :string           not null
#  registration              :string           not null
#  serial_number             :string
#  model                     :string
#  type_code                 :string
#  manufacturer_code         :string
#  owner                     :string
#  operator_name             :string
#  operator_icao             :string
#  engine_count              :integer
#  engine_model              :string
#  registration_date         :date
#  registration_country_code :string
#  manufacture_year          :integer
#  status                    :string
#  data                      :jsonb            default("{}"), not null
#  import_date               :datetime         not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  excluded                  :boolean          default(FALSE), not null
#  exclusion_reason          :string
#  excluded_at               :datetime
#  excluded_by               :string
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
