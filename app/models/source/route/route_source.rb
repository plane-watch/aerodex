# frozen_string_literal: true

# == Schema Information
#
# Table name: route_sources
#
#  id               :integer          not null, primary key
#  type             :string           not null
#  callsign         :string           not null
#  airline_code     :string           not null
#  airport_codes    :string           not null
#  data             :jsonb            default("{}"), not null
#  import_date      :datetime         not null
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_route_sources_on_airline_code       (airline_code)
#  index_route_sources_on_callsign_and_type  (callsign,type) UNIQUE
#  index_route_sources_on_data               (data)
#  index_route_sources_on_excluded           (excluded)
#

module Source
  module Route
    # Base class for route source records.
    #
    # Route sources store raw airline route data from external providers before
    # combining into canonical Route and RouteSegment records. Subclasses use
    # single-table inheritance via the `type` column.
    class RouteSource < ApplicationRecord
      include HasSourceExclusion

      self.table_name = 'route_sources'

      validates :callsign, presence: true
      validates :airline_code, presence: true
      validates :airport_codes, presence: true
      validates :import_date, presence: true

      # Splits the raw hyphenated airport codes into an ordered array.
      #
      # @return [Array<String>] The airport codes in flight order, e.g. %w[YSSY WSSS EGLL]
      def airport_code_list
        airport_codes.to_s.split('-')
      end
    end
  end
end
