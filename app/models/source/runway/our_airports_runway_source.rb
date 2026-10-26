# == Schema Information
#
# Table name: runway_sources
#
#  id                        :integer          not null, primary key
#  airport_ident             :string           not null
#  length_ft                 :decimal(, )
#  width_ft                  :decimal(, )
#  surface                   :string
#  lighted                   :boolean          default(FALSE)
#  closed                    :boolean          default(FALSE)
#  le_ident                  :string
#  le_latitude               :decimal(9, 6)
#  le_longitude              :decimal(9, 6)
#  le_elevation_ft           :decimal(, )
#  le_heading_deg            :decimal(, )
#  le_displaced_threshold_ft :decimal(, )
#  he_ident                  :string
#  he_latitude               :decimal(9, 6)
#  he_longitude              :decimal(9, 6)
#  he_elevation_ft           :decimal(, )
#  he_heading_deg            :decimal(, )
#  he_displaced_threshold_ft :decimal(, )
#  type                      :string           not null
#  import_date               :datetime         not null
#  data                      :jsonb            default("\"{}\""), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  excluded                  :boolean          default(FALSE), not null
#  exclusion_reason          :string
#  excluded_at               :datetime
#  excluded_by               :string
#
# Indexes
#
#  index_runway_sources_on_airport_ident          (airport_ident)
#  index_runway_sources_on_airport_le_ident_type  (airport_ident,le_ident,type) UNIQUE
#  index_runway_sources_on_data                   (data)
#  index_runway_sources_on_excluded               (excluded)
#

# frozen_string_literal: true

module Source
  module Runway
    # Runway data sourced from OurAirports.com
    #
    # OurAirports provides comprehensive runway data including:
    # - Dimensions (length, width in feet)
    # - Surface type (asphalt, concrete, grass, etc.)
    # - Lighting and operational status
    # - Detailed coordinates and headings for both runway ends
    # - Displaced threshold information
    #
    # @see https://ourairports.com/data/
    class OurAirportsRunwaySource < RunwaySource
    end
  end
end
