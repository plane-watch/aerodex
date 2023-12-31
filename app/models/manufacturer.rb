class Manufacturer < ApplicationRecord
  has_many :aircraft_types
  has_many :aircraft, through: :aircraft_types

  has_paper_trail
end
