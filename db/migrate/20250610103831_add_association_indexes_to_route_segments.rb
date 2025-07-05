class AddAssociationIndexesToRouteSegments < ActiveRecord::Migration[7.1]
  def change
    add_index :route_segments, :airport_id
    add_index :route_segments, :route_id
  end
end
