class CreateRouteSegments < ActiveRecord::Migration[7.0]
  def change
    create_table :route_segments do |t|
      t.integer :route_id
      t.integer :airport_id
      t.integer :order
      t.time :arrival_time
      t.time :departing_time

      t.timestamps
    end
  end
end
