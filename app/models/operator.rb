class Operator < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  has_many :aircraft_types, through: :aircraft

  has_many :routes
  has_many :route_segments, through: :routes

  meilisearch do
    attribute :name
    attribute :icao_callsign
    attribute :iata_callsign
    attribute :country
  end
end
