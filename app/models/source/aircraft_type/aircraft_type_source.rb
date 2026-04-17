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

module Source
  module AircraftType
    class AircraftTypeSource < ApplicationRecord
      include HasSourceExclusion
    end
  end
end
