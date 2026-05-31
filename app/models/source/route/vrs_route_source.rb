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
    # Source records for airline routes from the VRS (Virtual Radar Server)
    # standing-data GitHub repository.
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/routes/schema-01
    class VRSRouteSource < RouteSource
    end
  end
end
