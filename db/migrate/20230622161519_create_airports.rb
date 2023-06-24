class CreateAirports < ActiveRecord::Migration[7.0]
  def change
    create_table :airports do |t|
      t.string :name
      t.string :city
      t.string :country
      t.string :iata_code
      t.string :icao_code
      t.string :wmo_code
      t.integer :fir_id
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.decimal :altitude
      t.string :timezone

      t.timestamps
    end
  end
end
