class CreateManufacturerSources < ActiveRecord::Migration[7.1]
  def change
    create_table :manufacturer_sources do |t|
      t.string :name, null: false
      t.string :icao_code, null: false
      t.string :type, null: false
      t.string :country, null: true
      t.datetime :import_date, null: false
      t.jsonb  :data, null: false, default: '{}'

      t.timestamps
    end
  end
end
