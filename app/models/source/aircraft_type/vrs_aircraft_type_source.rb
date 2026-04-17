# == Schema Information
#
# Table name: aircraft_type_sources
#
#  id               :integer          not null, primary key
#  category         :string
#  created_at       :datetime         not null
#  data             :jsonb            default("{}"), not null
#  engine_type      :string
#  engines          :integer
#  excluded         :boolean          default(FALSE), not null
#  excluded_at      :datetime
#  excluded_by      :string
#  exclusion_reason :string
#  iata_code        :string
#  import_date      :datetime         not null
#  manufacturer     :string
#  name             :string
#  type             :string
#  type_code        :string
#  updated_at       :datetime         not null
#  wtc              :string
#
# Indexes
#
#  index_aircraft_type_sources_on_excluded       (excluded)
#  index_aircraft_type_sources_on_iata_and_type  (iata_code,type)
#

# frozen_string_literal: true

module Source
  module AircraftType
    # Source records for aircraft types from VRS (Virtual Radar Server) standing data.
    #
    # VRS model-type data is organised by the first letter of the ICAO type code
    # and includes manufacturer, model variants, engine info, and wake turbulence.
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/model-type/schema-01
    class VRSAircraftTypeSource < AircraftTypeSource
      # Maps VRS species codes to our category enum values
      SPECIES_TO_CATEGORY = {
        'L' => 'airplane',     # Landplane
        'S' => 'seaplane',     # Seaplane
        'A' => 'seaplane',     # Amphibian (can use water)
        'H' => 'helicopter',   # Helicopter
        'G' => 'helicopter',   # Gyrocopter (rotorcraft)
        'T' => 'airplane'      # Tilt-wing (like V-22 Osprey)
      }.freeze

      # Maps VRS engine type codes to our engine_type values
      ENGINE_TYPE_MAP = {
        'E' => 'Electric',
        'J' => 'Jet',
        'P' => 'Piston',
        'R' => 'Rocket',
        'T' => 'Turboprop'
      }.freeze

      # Converts the VRS species code to our category.
      #
      # @return [String, nil] The category name
      def category_from_species
        species_code = data&.dig('species_code')
        SPECIES_TO_CATEGORY[species_code]
      end

      # Converts the VRS engine type code to a readable name.
      #
      # @return [String, nil] The engine type name
      def engine_type_name
        ENGINE_TYPE_MAP[engine_type]
      end
    end
  end
end
