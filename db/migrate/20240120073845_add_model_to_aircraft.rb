class AddModelToAircraft < ActiveRecord::Migration[7.1]
  def change
    add_column :aircraft, :model, :string
  end
end
