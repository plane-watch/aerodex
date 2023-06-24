class CreateAircraft < ActiveRecord::Migration[7.0]
  def change
    create_table :aircraft do |t|
      t.string :icao
      t.integer :type_code_id
      t.string :serial_number
      t.integer :manufacture_year
      t.string :owner
      t.integer :operator_id
      t.string :registration
      t.date :registration_date
      t.string :registration_country
      t.integer :engine_count
      t.string :engine_model

      t.timestamps
    end
  end
end
