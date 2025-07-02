class AddAssociationIndexesToAircraftTypes < ActiveRecord::Migration[7.1]
  def change
    add_index :aircraft_types, :manufacturer_id
  end
end
