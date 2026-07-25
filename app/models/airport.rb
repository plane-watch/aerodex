# frozen_string_literal: true

# == Schema Information
#
# Table name: airports
#
#  id                           :integer          not null, primary key
#  name                         :string
#  city                         :string
#  country                      :string
#  iata_code                    :string
#  icao_code                    :string
#  wmo_code                     :string
#  flight_information_region_id :integer
#  latitude                     :decimal(9, 6)
#  longitude                    :decimal(9, 6)
#  altitude                     :decimal(, )
#  timezone                     :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  country_id                   :integer          not null
#  field_provenance             :jsonb            default("{}"), not null
#  last_combined_at             :datetime
#  airport_runways_count        :integer          default(0), not null
#
# Indexes
#
#  index_airports_on_country_id  (country_id)
#

# An airport or aerodrome, identified by its ICAO and IATA codes. Holds the
# runways it operates, the country and flight information region it sits in,
# and the route segments that call at it.
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
