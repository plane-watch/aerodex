# == Schema Information
#
# Table name: routes
#
#  id          :bigint           not null, primary key
#  call_sign   :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :string
#
class Route < ApplicationRecord
  has_many :route_segments
  belongs_to :operator

  has_paper_trail

end
