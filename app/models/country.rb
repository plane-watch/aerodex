# == Schema Information
#
# Table name: countries
#
#  id             :integer          not null, primary key
#  iso_2char_code :string
#  iso_3char_code :string
#  iso_num_code   :string
#  name           :string
#  capital        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

class Country < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  has_many :airports
  has_many :manufacturers
  has_many :operators
  has_many :flight_information_regions
  has_many :aircraft, foreign_key: :registration_country_id

  meilisearch do
    attribute :id
    attribute :name
    attribute :iso_2char_code
    attribute :iso_3char_code
    attribute :capital

    filterable_attributes %i[id name iso_2char_code iso_3char_code capital]
  end
end
