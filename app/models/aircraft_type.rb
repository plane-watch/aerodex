# == Schema Information
#
# Table name: aircraft_types
#
#  id               :integer          not null, primary key
#  manufacturer_id  :integer
#  type_code        :string
#  name             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  category         :integer
#  wtc              :string
#  engines          :integer
#  engine_type      :string
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  aircraft_count   :integer          default("0"), not null
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
    attribute :manufacturer
    attribute :category

    filterable_attributes %i[id name type_code manufacturer category]
  end

  def full_name
    manufacturer&.name.present? ? "#{manufacturer.name} #{name}" : name
  end
end
