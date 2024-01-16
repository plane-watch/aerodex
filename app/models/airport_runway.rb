# == Schema Information
#
# Table name: airport_runways
#
#  id          :bigint           not null, primary key
#  heading     :decimal(, )
#  length      :decimal(, )
#  runway_name :string
#  width       :decimal(, )
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  airport_id  :integer
#
class AirportRunway < ApplicationRecord
  belongs_to :airport
  has_one :flight_information_region, through: :airport

  has_paper_trail

end
