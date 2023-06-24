class CreateOperators < ActiveRecord::Migration[7.0]
  def change
    create_table :operators do |t|
      t.string :name
      t.string :country
      t.string :icao_callsign
      t.string :iata_callsign
      t.string :positioning_callsign_pattern
      t.string :charter_callsign_pattern

      t.timestamps
    end
  end
end
