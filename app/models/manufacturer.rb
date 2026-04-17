# == Schema Information
#
# Table name: manufacturers
#
#  id                   :integer          not null, primary key
#  aircraft_count       :integer          default(0), not null
#  aircraft_types_count :integer          default(0), not null
#  alt_names            :jsonb
#  country_id           :integer
#  created_at           :datetime         not null
#  field_provenance     :jsonb            default("{}"), not null
#  icao_code            :string
#  last_combined_at     :datetime
#  name                 :string
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_manufacturers_on_country_id  (country_id)
#

class Manufacturer < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  has_many :aircraft_types
  has_many :aircraft, through: :aircraft_types
  belongs_to :country, optional: true

  has_paper_trail
  # Preload associations for MeiliSearch reindexing to avoid N+1 queries
  scope :meilisearch_import, -> { includes(:country) }

  meilisearch do
    attribute :id
    attribute :name
    attribute :icao_code
    attribute :country do
      country&.name
    end

    filterable_attributes %i[id name icao_code country]
  end
end
