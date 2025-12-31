# == Schema Information
#
# Table name: operators
#
#  id               :integer          not null, primary key
#  name             :string
#  icao_code        :string
#  iata_code        :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  country_id       :integer
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  aircraft_count   :integer          default("0"), not null
#
# Indexes
#
#  index_operators_on_country_id  (country_id)
#

## Notes:
## Consider normalising the call sign patterns into a separate table
class Operator < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  has_many :aircraft
  has_many :aircraft_types, through: :aircraft

  has_many :routes
  has_many :route_segments, through: :routes

  belongs_to :country, optional: true, counter_cache: :operators_count

  validates :name, presence: true, allow_blank: false, uniqueness: { scope: %i[country_id icao_code], case_sensitive: false }
  validates :icao_code, allow_blank: true, format: { with: /\A[A-Z0-9]{3}\z/ }, uniqueness: { case_sensitive: false } # , scope: :active }
  validates :iata_code, allow_blank: true, format: { with: /\A[A-Z0-9]{2}\z/ }

  after_create :index!

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :name
    attribute :icao_code
    attribute :iata_code
    attribute :country

    filterable_attributes %i[id name icao_code iata_code country]
  end
end
