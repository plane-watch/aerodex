# frozen_string_literal: true
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

module Source
  module Aircraft
    # Source records for aircraft from VRS (Virtual Radar Server) standing data.
    #
    # VRS aggregates crowdsourced aircraft data from users worldwide.
    # This source provides broad coverage but may have varying accuracy.
    # Data is organised by ICAO Mode-S code segments in the repository.
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/aircraft/schema-01
    class VRSAircraftSource < AircraftSource
      # VRS data is global - country is derived from registration prefix
      # during import, not set as a default.
    end
  end
end
