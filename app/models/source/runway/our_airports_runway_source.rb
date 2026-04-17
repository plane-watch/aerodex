# == Schema Information
#
# Table name: runway_sources
#
#  id                        :integer          not null, primary key
#  airport_ident             :string           not null
#  closed                    :boolean          default(FALSE)
#  created_at                :datetime         not null
#  data                      :jsonb            default("\"{}\""), not null
#  excluded                  :boolean          default(FALSE), not null
#  excluded_at               :datetime
#  excluded_by               :string
#  exclusion_reason          :string
#  he_displaced_threshold_ft :decimal(, )
#  he_elevation_ft           :decimal(, )
#  he_heading_deg            :decimal(, )
#  he_ident                  :string
#  he_latitude               :decimal(9, 6)
#  he_longitude              :decimal(9, 6)
#  import_date               :datetime         not null
#  le_displaced_threshold_ft :decimal(, )
#  le_elevation_ft           :decimal(, )
#  le_heading_deg            :decimal(, )
#  le_ident                  :string
#  le_latitude               :decimal(9, 6)
#  le_longitude              :decimal(9, 6)
#  length_ft                 :decimal(, )
#  lighted                   :boolean          default(FALSE)
#  surface                   :string
#  type                      :string           not null
#  updated_at                :datetime         not null
#  width_ft                  :decimal(, )
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
