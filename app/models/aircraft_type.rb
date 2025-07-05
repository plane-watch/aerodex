# == Schema Information
#
# Table name: aircraft_types
#
#  id              :bigint           not null, primary key
#  category        :integer
#  name            :string
#  type_code       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  manufacturer_id :integer
#
# Indexes
#
#  index_aircraft_types_on_manufacturer_id  (manufacturer_id)
#
class AircraftType < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  belongs_to :manufacturer
  enum category: { airplane: 0, helicopter: 1, seaplane: 2, glider: 3, balloon: 4 }

  has_paper_trail
  meilisearch do
    attribute :name
  end

  def full_name
    "#{manufacturer.name} #{name}"
  end
end
