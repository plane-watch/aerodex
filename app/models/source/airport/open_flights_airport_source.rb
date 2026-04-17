# == Schema Information
#
# Table name: airport_sources
#
#  id               :integer          not null, primary key
#  airport_type     :string
#  city             :string
#  country_code     :string
#  created_at       :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  elevation        :decimal(, )
#  excluded         :boolean          default(FALSE), not null
#  excluded_at      :datetime
#  excluded_by      :string
#  exclusion_reason :string
#  iata_code        :string
#  icao_code        :string
#  ident            :string
#  import_date      :datetime         not null
#  latitude         :decimal(9, 6)
#  longitude        :decimal(9, 6)
#  municipality     :string
#  name             :string           not null
#  timezone         :string
#  type             :string           not null
#  updated_at       :datetime         not null
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
