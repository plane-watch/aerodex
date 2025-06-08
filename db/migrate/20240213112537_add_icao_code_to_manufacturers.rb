class AddICAOCodeToManufacturers < ActiveRecord::Migration[7.1]
  def change
    add_column :manufacturers, :icao_code, :string
  end
end
