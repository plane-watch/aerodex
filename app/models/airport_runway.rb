# == Schema Information
#
# Table name: airport_runways
#
#  id          :integer          not null, primary key
#  airport_id  :integer
#  runway_name :string
#  heading     :decimal(, )
#  length      :decimal(, )
#  width       :decimal(, )
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

class AirportRunway < ApplicationRecord
  include MeiliSearch::Rails
  belongs_to :airport
  has_one :flight_information_region, through: :airport

  has_paper_trail
end
