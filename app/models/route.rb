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
  has_many :route_segments
  belongs_to :operator

  has_paper_trail
end
