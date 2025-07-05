class RenameOperatorFields < ActiveRecord::Migration[7.1]
  def change
    rename_column :operators, :iata_callsign, :iata_code
    rename_column :operators, :icao_callsign, :icao_code
    remove_column :operators, :positioning_callsign_pattern
    remove_column :operators, :charter_callsign_pattern
  end
end
