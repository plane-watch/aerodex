# == Schema Information
#
# Table name: operators
#
#  id         :bigint           not null, primary key
#  country    :string
#  iata_code  :string
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

## Notes:
## Consider normalising the call sign patterns into a separate table
class Operator < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  has_many :aircraft_types, through: :aircraft

  has_many :routes
  has_many :route_segments, through: :routes

  validates :name, presence: true, allow_blank: false
  validates :icao_code, allow_blank: true, format: { with: /\A[A-Z0-9]{3}\z/ }, uniqueness: { case_sensitive: false } # , scope: :active }
  validates :iata_code, allow_blank: true, format: { with: /\A[A-Z0-9]{2}\z/ }

  has_paper_trail
  meilisearch do
    attribute :name
    attribute :icao_code
    attribute :iata_code
    attribute :country
  end
end
