class AddImportFieldsToAircraftTypeSources < ActiveRecord::Migration[8.0]
  def change
    add_column :aircraft_type_sources, :import_date, :datetime, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    add_column :aircraft_type_sources, :data, :jsonb, null: false, default: {}
  end
end
