# == Schema Information
#
# Table name: manufacturers
#
#  id         :bigint           not null, primary key
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Manufacturer < ApplicationRecord
  has_many :aircraft_types
  has_many :aircraft, through: :aircraft_types

  has_paper_trail
end
