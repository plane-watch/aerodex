class AddCountryToManufacturer < ActiveRecord::Migration[7.1]
  def change
    add_reference :manufacturers, :country, null: true, foreign_key: true
  end
end
