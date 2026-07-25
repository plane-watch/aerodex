# frozen_string_literal: true

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
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_aircraft_type_sources_on_excluded       (excluded)
#  index_aircraft_type_sources_on_iata_and_type  (iata_code,type)
#

module Source
  module AircraftType
    class CfappsICAOIntAircraftTypeSource < AircraftTypeSource
    end
  end
end
