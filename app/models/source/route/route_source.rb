# frozen_string_literal: true

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
