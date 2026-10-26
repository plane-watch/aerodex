# frozen_string_literal: true

# Creates the user_contributions table for tracking user-submitted data changes.
# Also adds contribution_trust_score to the users table.
class CreateUserContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_contributions do |t|
      t.references :user, null: false, foreign_key: true

      # Polymorphic reference to the entity being modified
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false

      # The specific field being changed
      t.string :field_name, null: false

      # The previous and proposed values (stored as JSONB to handle various data types)
      t.jsonb :old_value
      t.jsonb :new_value

      # Workflow status managed by AASM state machine
      t.string :status, null: false, default: 'pending'

      # Optional notes from the contributor or reviewer
      t.text :notes

      # Reviewer information (for approved/rejected contributions)
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at

      t.timestamps
    end

    # Index for looking up contributions by entity
    add_index :user_contributions, %i[entity_type entity_id field_name], name: 'idx_user_contributions_entity'

    # Index for filtering by status (for the review queue)
    add_index :user_contributions, :status

    # Add trust score to users for weighting their contributions
    add_column :users, :contribution_trust_score, :integer, default: 50, null: false
  end
end
