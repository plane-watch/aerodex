# frozen_string_literal: true

class CreateStagedBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :staged_batches, id: :uuid do |t|
      t.string :processor_type, null: false
      t.string :entity_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :summary, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :job_id
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :applied_at
      t.datetime :reviewed_at
      t.text :notes
      t.text :error_message

      t.timestamps
    end

    add_index :staged_batches, :status
    add_index :staged_batches, :entity_type
    add_index :staged_batches, :job_id
    add_index :staged_batches, :created_at
  end
end
