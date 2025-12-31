# == Schema Information
#
# Table name: airport_sources
#
#  id               :integer          not null, primary key
#  icao_code        :string
#  iata_code        :string
#  ident            :string
#  name             :string           not null
#  city             :string
#  municipality     :string
#  country_code     :string
#  latitude         :decimal(9, 6)
#  longitude        :decimal(9, 6)
#  elevation        :decimal(, )
#  timezone         :string
#  airport_type     :string
#  type             :string           not null
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  excluded         :boolean          default("false"), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_airport_sources_on_data            (data)
#  index_airport_sources_on_excluded        (excluded)
#  index_airport_sources_on_iata_and_type   (iata_code,type)
#  index_airport_sources_on_icao_and_type   (icao_code,type)
#  index_airport_sources_on_ident_and_type  (ident,type)
#

# frozen_string_literal: true

module Source
  module Airport
    # Airport data sourced from OpenFlights.org
    #
    # OpenFlights provides airport data with IATA/ICAO codes, coordinates, and timezone.
    # Data is from January 2017 vintage, so less current than OurAirports.
    #
    # @see https://openflights.org/data
    class OpenFlightsAirportSource < AirportSource
      # OpenFlights uses city field rather than municipality
      def location_name
        city
      end
    end
  end
end
