class AddAssociationIndexesToAircraft < ActiveRecord::Migration[7.1]
  def change
    add_index :aircraft, :aircraft_type_id
    add_index :aircraft, :operator_id
  end
end
