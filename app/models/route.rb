# == Schema Information
#
# Table name: routes
#
#  id          :integer          not null, primary key
#  call_sign   :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          not null
#
# Indexes
#
#  index_routes_on_operator_id  (operator_id)
#

class Route < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  has_many :route_segments
  belongs_to :operator

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :call_sign
    attribute :operator

    filterable_attributes %i[id call_sign operator]
  end
end
