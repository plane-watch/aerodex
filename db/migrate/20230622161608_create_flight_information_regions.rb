class CreateFlightInformationRegions < ActiveRecord::Migration[7.0]
  def change
    create_table :flight_information_regions do |t|
      t.string :icao_code
      t.string :region
      t.column :bounds, 'polygon', null: true
      t.timestamps
    end
  end
end
