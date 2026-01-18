# frozen_string_literal: true
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
#  excluded         :boolean          default("false"), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_operator_sources_on_data      (data)
#  index_operator_sources_on_excluded  (excluded)
#

module Source
  module Operator
    # Source records from airlinecodes.info - a community-maintained database of
    # airline ICAO/IATA codes with country and callsign information.
    #
    # Data attribution: https://airlinecodes.info
    # This source is particularly useful for enriching operators with country data.
    class AirlineCodesOperatorSource < OperatorSource
      # Returns the attribution string for this data source.
      #
      # @return [String] The attribution text
      def self.attribution
        'Data sourced from airlinecodes.info'
      end

      # Returns the source URL for a given ICAO code.
      #
      # @param icao_code [String] The ICAO code
      # @return [String] The URL for that airline's page
      def self.source_url(icao_code)
        "https://airlinecodes.info/#{icao_code}"
      end
    end
  end
end
