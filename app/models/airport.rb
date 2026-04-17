# == Schema Information
#
# Table name: airports
#
#  id                           :integer          not null, primary key
#  airport_runways_count        :integer          default(0), not null
#  altitude                     :decimal(, )
#  city                         :string
#  country                      :string
#  country_id                   :integer          not null
#  created_at                   :datetime         not null
#  field_provenance             :jsonb            default("{}"), not null
#  flight_information_region_id :integer
#  iata_code                    :string
#  icao_code                    :string
#  last_combined_at             :datetime
#  latitude                     :decimal(9, 6)
#  longitude                    :decimal(9, 6)
#  name                         :string
#  timezone                     :string
#  updated_at                   :datetime         not null
#  wmo_code                     :string
#
# Indexes
#
#  index_airports_on_country_id  (country_id)
#

class Airport < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  belongs_to :flight_information_region, optional: true
  has_many :airport_runways
  has_many :route_segments
  belongs_to :country, optional: true, counter_cache: true

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :name
    attribute :city
    attribute :icao_code
    attribute :iata_code
    attribute :country do
      country&.name
    end

    filterable_attributes %i[id name city icao_code iata_code country]
  end
end
