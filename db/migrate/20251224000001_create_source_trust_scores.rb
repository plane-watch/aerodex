# frozen_string_literal: true

# Creates the source_trust_scores table for storing trust levels per source/entity/field combination.
# This allows database-level overrides of the default trust values defined in SourceConfig.
class CreateSourceTrustScores < ActiveRecord::Migration[8.0]
  def change
    create_table :source_trust_scores do |t|
      # The canonical entity type this trust score applies to (e.g., "Operator", "Aircraft")
      t.string :entity_type, null: false

      # The source class name (e.g., "VRSDataOperatorSource", "CASAAircraftSource")
      t.string :source_type, null: false

      # Optional field name for field-specific overrides. When null, applies as the default for all fields.
      t.string :field_name

      # The base trust score (0-100). Higher values indicate more reliable data.
      t.integer :base_trust, null: false, default: 50

      t.timestamps
    end

    # Ensures uniqueness for the entity/source/field combination.
    # Allows one default (field_name: null) and multiple field-specific overrides per entity/source pair.
    add_index :source_trust_scores,
              %i[entity_type source_type field_name],
              unique: true,
              name: 'idx_source_trust_scores_unique'
  end
end