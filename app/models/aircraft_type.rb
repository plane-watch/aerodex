class AircraftType < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  belongs_to :manufacturer

  has_paper_trail
  meilisearch do
    attribute :name
  end
end
