class Route < ApplicationRecord
  has_many :route_segments
  belongs_to :operator

end
