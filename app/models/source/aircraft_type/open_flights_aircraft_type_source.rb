# == Schema Information
#
# Table name: aircraft_type_sources
#
#  id               :integer          not null, primary key
#  name             :string
#  type_code        :string
#  manufacturer     :string
#  wtc              :string
#  category         :string
#  engines          :integer
#  engine_type      :string
#  type             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  iata_code        :string
#  import_date      :datetime         not null
#  data             :jsonb            default("{}"), not null
#  excluded         :boolean          default("false"), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_aircraft_type_sources_on_excluded       (excluded)
#  index_aircraft_type_sources_on_iata_and_type  (iata_code,type)
#

# frozen_string_literal: true

module Source
  module AircraftType
    # Aircraft type data sourced from OpenFlights.org
    #
    # OpenFlights provides aircraft type data with IATA codes, which complements
    # the ICAO type codes from the CFAPPS ICAO source.
    #
    # @see https://openflights.org/data
    class OpenFlightsAircraftTypeSource < AircraftTypeSource
    end
  end
end
