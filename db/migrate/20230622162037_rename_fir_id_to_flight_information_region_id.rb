class RenameFIRIdToFlightInformationRegionId < ActiveRecord::Migration[7.0]
  def up
    rename_column :airports, :fir_id, :flight_information_region_id
  end

  def down
    rename_column :airports, :flight_information_region_id, :fir_id
  end
end
