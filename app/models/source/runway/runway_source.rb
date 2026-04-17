# frozen_string_literal: true
# == Schema Information
#
# Table name: runway_sources
#
#  id                        :integer          not null, primary key
#  airport_ident             :string           not null
#  length_ft                 :decimal(, )
#  width_ft                  :decimal(, )
#  surface                   :string
#  lighted                   :boolean          default("false")
#  closed                    :boolean          default("false")
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
#  excluded                  :boolean          default("false"), not null
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

module Source
  module Runway
    # Base class for runway data sources.
    #
    # Runways are identified by their airport (via airport_ident) and their
    # low-end identifier (le_ident). Each runway has two ends, conventionally
    # named by their magnetic heading (e.g., "16L" and "34R" for opposite ends).
    class RunwaySource < ApplicationRecord
      include MeiliSearch::Rails
      include HasSourceExclusion

      self.table_name = 'runway_sources'

      serialize :data, coder: JsonbSerializer

      validates :airport_ident, presence: true

      # Scopes for querying
      scope :for_airport, ->(ident) { where(airport_ident: ident) }
      scope :with_le_ident, ->(le_ident) { where(le_ident: le_ident) if le_ident.present? }

      # Returns a display name for the runway (e.g., "16L/34R")
      def display_name
        if le_ident.present? && he_ident.present?
          "#{le_ident}/#{he_ident}"
        elsif le_ident.present?
          le_ident
        elsif he_ident.present?
          he_ident
        else
          'Unknown'
        end
      end

      # Returns length in metres (converted from feet)
      def length_metres
        return nil unless length_ft

        (length_ft * 0.3048).round(1)
      end

      # Returns width in metres (converted from feet)
      def width_metres
        return nil unless width_ft

        (width_ft * 0.3048).round(1)
      end
    end
  end
end
