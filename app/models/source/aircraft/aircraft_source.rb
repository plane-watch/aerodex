# frozen_string_literal: true
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

module Source
  module Aircraft
    # Base class for aircraft source records.
    #
    # Aircraft sources store raw data from various civil aviation authorities
    # and databases before combining into canonical Aircraft records.
    class AircraftSource < ApplicationRecord
      include HasSourceExclusion

      self.table_name = 'aircraft_sources'

      validates :icao, presence: true
      validates :registration, presence: true
      validates :import_date, presence: true
    end
  end
end
