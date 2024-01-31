class AddAddtionalFieldsToAircraft < ActiveRecord::Migration[7.0]
  def change
    add_column :aircraft, :cabin_configuration, :string
    add_column :aircraft, :aircraft_name, :string
    add_column :aircraft, :status, :integer, size: 1, default: 0
  end
end
