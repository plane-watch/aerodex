# frozen_string_literal: true

# == Schema Information
#
# Table name: airport_runways
#
#  id               :integer          not null, primary key
#  airport_id       :integer
#  runway_name      :string
#  heading          :decimal(, )
#  length           :decimal(, )
#  width            :decimal(, )
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  le_ident         :string
#  he_ident         :string
#  surface          :string
#  lighted          :boolean          default(FALSE)
#  closed           :boolean          default(FALSE)
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#

# A single runway at an Airport. Each end is recorded separately: `le_` fields
# describe the lower-numbered end and `he_` fields the higher-numbered one.
class AirportRunway < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  belongs_to :airport, counter_cache: true
  has_one :flight_information_region, through: :airport

  has_paper_trail

  meilisearch do
    attribute :id
    attribute :runway_name
    attribute :le_ident
    attribute :he_ident
    attribute :surface
    attribute :airport_icao do
      airport&.icao_code
    end
    attribute :airport_name do
      airport&.name
    end

    filterable_attributes %i[airport_icao surface lighted closed]
    searchable_attributes %i[runway_name le_ident he_ident airport_icao airport_name]
  end

  # Scope used by MeiliSearch for reindexing - preloads airport to avoid N+1
  def self.meilisearch_import
    includes(:airport)
  end

  # Returns a display name for the runway (e.g., "16L/34R")
  def display_name
    if le_ident.present? && he_ident.present?
      "#{le_ident}/#{he_ident}"
    elsif runway_name.present?
      runway_name
    else
      'Unknown'
    end
  end
end
