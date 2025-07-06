class CreateAircraftTypeSources < ActiveRecord::Migration[8.0]
  def change
    create_table :aircraft_type_sources do |t|
      t.string :name
      t.string :type_code
      t.string :manufacturer
      t.string :wtc
      t.string :category
      t.integer :engines
      t.string :engine_type

      t.timestamps
    end
  end
end
