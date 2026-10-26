# frozen_string_literal: true

# == Schema Information
#
# Table name: flight_information_regions
#
#  id         :integer          not null, primary key
#  icao_code  :string
#  region     :string
#  bounds     :polygon
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :integer          not null
#
# Indexes
#
#  index_flight_information_regions_on_country_id  (country_id)
#

# A flight information region: the block of airspace within which a country
# provides flight information and alerting services. Groups the airports, and
# through them the runways, that fall inside it.
class FlightInformationRegion < ApplicationRecord
  include MeiliSearch::Rails
  belongs_to :country
  has_many :airports
  has_many :airport_runways, through: :airports

  has_paper_trail
end
