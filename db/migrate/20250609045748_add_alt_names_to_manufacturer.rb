class AddAltNamesToManufacturer < ActiveRecord::Migration[7.1]
  def change
    add_column :manufacturers, :alt_names, :jsonb
  end
end
