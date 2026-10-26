# frozen_string_literal: true

class CreateStagedChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :staged_changes do |t|
      t.references :staged_batch, null: false, foreign_key: true, type: :uuid
      t.string :record_type, null: false
      t.bigint :record_id
      t.string :record_identifier, null: false
      t.integer :operation, null: false
      t.jsonb :diff, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :staged_changes, %i[record_type record_id]
    add_index :staged_changes, :record_identifier
  end
end
