class CreateAirportRunways < ActiveRecord::Migration[7.0]
  def change
    create_table :airport_runways do |t|
      t.integer :airport_id
      t.string :runway_name
      t.decimal :heading
      t.decimal :length
      t.decimal :width

      t.timestamps
    end
  end
end
