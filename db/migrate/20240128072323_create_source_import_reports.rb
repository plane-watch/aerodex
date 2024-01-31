class CreateSourceImportReports < ActiveRecord::Migration[7.0]
  def change
    create_table :source_import_reports do |t|
      t.string :importer_type
      t.jsonb :import_errors
      t.integer :records_processed
      t.boolean :success
      t.timestamps
    end
  end
end
