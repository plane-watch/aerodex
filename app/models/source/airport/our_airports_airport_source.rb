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
    # Airport data sourced from OurAirports.com
    #
    # OurAirports provides comprehensive, daily-updated airport data with:
    # - Multiple identifier types (ICAO, IATA, GPS code, local code, ident)
    # - Airport type classification (large_airport, medium_airport, small_airport, heliport, etc.)
    # - Municipality and region information
    # - Wikipedia and home page links
    #
    # The ident field is OurAirports' primary identifier and may differ from ICAO code
    # for airports without an ICAO designation (common for small US airports).
    #
    # @see https://ourairports.com/data/
    class OurAirportsAirportSource < AirportSource
      # OurAirports uses municipality field
      def location_name
        municipality
      end

      # Returns the ISO region code stored in the data field
      def iso_region
        data['iso_region']
      end

      # Returns the continent code stored in the data field
      def continent
        data['continent']
      end

      # Returns whether the airport has scheduled service
      def scheduled_service?
        data['scheduled_service'] == 'yes'
      end
    end
  end
end
