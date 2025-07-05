# == Schema Information
#
# Table name: manufacturers
#
#  id         :bigint           not null, primary key
#  alt_names  :jsonb
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :bigint
#
# Indexes
#
#  index_manufacturers_on_country_id  (country_id)
#
# Foreign Keys
#
#  fk_rails_...  (country_id => countries.id)
#
class Manufacturer < ApplicationRecord
  include MeiliSearch::Rails
  has_many :aircraft_types
  has_many :aircraft, through: :aircraft_types
  belongs_to :country, optional: true

  has_paper_trail
end
