# == Schema Information
#
# Table name: aircraft_types
#
#  id              :integer          not null, primary key
#  manufacturer_id :integer
#  type_code       :string
#  name            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  category        :integer
#  wtc             :string
#  engines         :integer
#  engine_type     :string
#
# Indexes
#
#  index_aircraft_types_on_manufacturer_id  (manufacturer_id)
#

class AircraftType < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  has_many :aircraft
  belongs_to :manufacturer
  enum :category, { airplane: 0, helicopter: 1, seaplane: 2, glider: 3, balloon: 4 }

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :name
    attribute :type_code
    attribute :manufacturer
    attribute :category

    filterable_attributes %i[id name type_code manufacturer category]
  end

  def full_name
    "#{manufacturer.name} #{name}"
  end
end
