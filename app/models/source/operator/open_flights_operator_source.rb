# == Schema Information
#
# Table name: operator_sources
#
#  id               :integer          not null, primary key
#  icao_code        :string
#  iata_code        :string
#  name             :string
#  type             :string           not null
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_operator_sources_on_data      (data)
#  index_operator_sources_on_excluded  (excluded)
#

# frozen_string_literal: true

module Source
  module Operator
    # Operator data sourced from OpenFlights.org
    #
    # OpenFlights provides airline data with IATA/ICAO codes, callsigns,
    # and active status. Data is from January 2012 vintage.
    #
    # @see https://openflights.org/data
    class OpenFlightsOperatorSource < OperatorSource
      # Returns whether the airline is currently active
      def active?
        data['active'] == 'Y'
      end

      # Returns the radio callsign for the airline
      def callsign
        data['callsign']
      end

      # Returns the country name (not ISO code)
      def country_name
        data['country']
      end
    end
  end
end
