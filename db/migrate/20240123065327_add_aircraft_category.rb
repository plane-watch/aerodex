class AddAircraftCategory < ActiveRecord::Migration[7.1]
  def up
    add_column :aircraft_types, :category, :integer, limit: 2
  end

  def down
    remove_column :aircraft_types, :category
  end
end
