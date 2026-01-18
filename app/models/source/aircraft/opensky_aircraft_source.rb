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
#  excluded                  :boolean          default("false"), not null
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
    # Source records for aircraft from OpenSky Network's aircraft database.
    #
    # OpenSky aggregates aircraft metadata from various sources including
    # national registries and crowdsourced data. Key fields include owner
    # information which is often missing from other sources.
    #
    # @see https://opensky-network.org/datasets/metadata/
    class OpenskyAircraftSource < AircraftSource
      # OpenSky has good owner data from FAA and other registries
      # This makes it valuable for filling ownership gaps.
    end
  end
end
