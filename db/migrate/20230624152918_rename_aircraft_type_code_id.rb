class RenameAircraftTypeCodeId < ActiveRecord::Migration[7.0]
  def up
    rename_column :aircraft, :type_code_id, :aircraft_type_id
  end
  def down
    rename_column :aircraft, :aircraft_type_id, :type_code_id
  end
end
