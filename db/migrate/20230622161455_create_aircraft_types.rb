class CreateAircraftTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :aircraft_types do |t|
      t.integer :manufacturer_id
      t.string :type_code
      t.string :name

      t.timestamps
    end
  end
end
