class AddCountryToFlightInformationRegion < ActiveRecord::Migration[7.1]
  def change
    add_reference :flight_information_regions, :country, null: false, foreign_key: true
  end
end
