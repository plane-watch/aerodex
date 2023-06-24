class AircraftType < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  belongs_to :manufacturer

  meilisearch do
    attribute :name
  end
end
