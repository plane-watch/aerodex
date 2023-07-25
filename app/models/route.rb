class Route < ApplicationRecord
  has_many :route_segments
  belongs_to :operator

  has_paper_trail

end
