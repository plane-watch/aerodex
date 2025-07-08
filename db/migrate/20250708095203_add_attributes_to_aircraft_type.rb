class AddAttributesToAircraftType < ActiveRecord::Migration[8.0]
  def change
    add_column :aircraft_types, :wtc, :string
    add_column :aircraft_types, :engines, :integer
    add_column :aircraft_types, :engine_type, :string
  end
end
