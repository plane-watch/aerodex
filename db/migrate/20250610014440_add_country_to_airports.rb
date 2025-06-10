class AddCountryToAirports < ActiveRecord::Migration[7.1]
  def change
    add_reference :airports, :country, null: false, foreign_key: true
  end
end
