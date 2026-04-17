# == Schema Information
#
# Table name: aircraft_types
#
#  id               :integer          not null, primary key
#  aircraft_count   :integer          default(0), not null
#  category         :integer
#  created_at       :datetime         not null
#  engine_type      :string
#  engines          :integer
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  manufacturer_id  :integer
#  name             :string
#  type_code        :string
#  updated_at       :datetime         not null
#  wtc              :string
#
# Indexes
#
#  index_aircraft_types_on_manufacturer_id     (manufacturer_id)
#  index_aircraft_types_on_type_code_and_name  (type_code,name) UNIQUE
#

class AircraftType < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  has_many :aircraft
  belongs_to :manufacturer, counter_cache: true
  enum :category, { airplane: 0, helicopter: 1, seaplane: 2, glider: 3, balloon: 4 }

  has_paper_trail

  # Preload associations for MeiliSearch reindexing to avoid N+1 queries
  scope :meilisearch_import, -> { includes(:manufacturer) }

  meilisearch do
    attribute :id
    attribute :name
    attribute :type_code
    attribute :manufacturer do
      manufacturer&.name
    end
    attribute :category

    filterable_attributes %i[id name type_code manufacturer category]
  end

  def full_name
    manufacturer&.name.present? ? "#{manufacturer.name} #{name}" : name
  end
end
