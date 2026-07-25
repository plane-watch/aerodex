class CreateOperatorMatchDecisions < ActiveRecord::Migration[8.0]
  def change
    create_table :operator_match_decisions do |t|
      t.references :operator, null: false, foreign_key: true
      t.string :matched_name, null: false
      t.string :matched_icao_code
      t.integer :decision_type, null: false, default: 0
      t.string :decided_by
      t.text :notes

      t.timestamps
    end

    # Index for looking up decisions by matched name (used during aircraft import)
    add_index :operator_match_decisions, :matched_name

    # Index for looking up decisions by matched ICAO code
    add_index :operator_match_decisions, :matched_icao_code

    # Unique constraint: one decision per (matched_name, matched_icao_code) pair
    add_index :operator_match_decisions, %i[matched_name matched_icao_code],
              unique: true,
              name: 'idx_match_decisions_unique_name_icao'
  end
end
