# == Schema Information
#
# Table name: countries
#
#  id             :bigint           not null, primary key
#  capital        :string
#  iso_2char_code :string
#  iso_3char_code :string
#  iso_num_code   :string
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Country < ApplicationRecord
  include MeiliSearch::Rails

  has_many :airports
  has_many :manufacturers
  has_many :operators
  has_many :flight_information_regions
  has_many :aircraft, foreign_key: :registration_country_id
end
