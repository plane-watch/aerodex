class CreateOperatorSources < ActiveRecord::Migration[7.0]
  def change
    create_table "operator_sources" do |t|
      t.string "icao_code", null: true
      t.string "iata_code", null: true
      t.string "name", null: true
      t.string "type", null: false
      t.datetime "import_date", null: false
      t.jsonb "data", null: false, default: '{}'
      t.timestamps
    end
    add_index :operator_sources, :data, using: :gin
  end
end
