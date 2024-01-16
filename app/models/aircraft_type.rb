# == Schema Information
#
# Table name: aircraft_types
#
#  id              :bigint           not null, primary key
#  name            :string
#  type_code       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  manufacturer_id :integer
#
class AircraftType < ApplicationRecord
  include MeiliSearch::Rails

  has_many :aircraft
  belongs_to :manufacturer

  has_paper_trail
  meilisearch do
    attribute :name
  end
end
