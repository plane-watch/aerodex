# frozen_string_literal: true

class AddFieldsToAirportRunways < ActiveRecord::Migration[8.0]
  def change
    change_table :airport_runways, bulk: true do |t|
      # Runway end identifiers (e.g., "16L" / "34R")
      t.string :le_ident
      t.string :he_ident

      # Additional runway properties
      t.string :surface # e.g., "ASP", "CON", "GRS"
      t.boolean :lighted, default: false
      t.boolean :closed, default: false

      # Provenance tracking (consistent with other canonical models)
      t.jsonb :field_provenance, default: {}, null: false
      t.datetime :last_combined_at
    end
  end
end

