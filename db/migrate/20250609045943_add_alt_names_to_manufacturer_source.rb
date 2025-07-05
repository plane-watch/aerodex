class AddAltNamesToManufacturerSource < ActiveRecord::Migration[7.1]
  def change
    add_column :manufacturer_sources, :alt_names, :jsonb
  end
end
