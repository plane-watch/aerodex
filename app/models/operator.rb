# == Schema Information
#
# Table name: operators
#
#  id                           :bigint           not null, primary key
#  charter_callsign_pattern     :string
#  country                      :string
#  iata_callsign                :string
#  icao_callsign                :string
#  name                         :string
#  positioning_callsign_pattern :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null

## Notes:
## Consider normalising the call sign patterns into a separate table
class Operator < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  has_many :aircraft_types, through: :aircraft

  has_many :routes
  has_many :route_segments, through: :routes

  validates :name, presence: true, allow_blank: false
  validates :icao_callsign, presence: true, allow_blank: false, format: { with: /\A[A-Z]{3}\z/ }, uniqueness: { case_sensitive: false } #, scope: :active }
  validates :iata_callsign, presence: true, allow_blank: false, format: { with: /\A[A-Z]{2}\z/ }
  validates :positioning_callsign_pattern, callsign_pattern: true, allow_blank: true
  validates :charter_callsign_pattern, callsign_pattern: true, allow_blank: true

  has_paper_trail
  meilisearch do
    attribute :name
    attribute :icao_callsign
    attribute :iata_callsign
    attribute :country
  end

end
