# == Schema Information
#
# Table name: manufacturers
#
#  id         :integer          not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  icao_code  :string
#  alt_names  :jsonb
#  country_id :integer
#
# Indexes
#
#  index_manufacturers_on_country_id  (country_id)
#

class Manufacturer < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  has_many :aircraft_types
  has_many :aircraft, through: :aircraft_types
  belongs_to :country, optional: true

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :name
    attribute :icao_code
    attribute :country

    filterable_attributes %i[id name icao_code country]
  end
end
