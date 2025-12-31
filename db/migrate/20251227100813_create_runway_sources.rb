# frozen_string_literal: true

class CreateRunwaySources < ActiveRecord::Migration[8.0]
  def change
    create_table :runway_sources do |t|
      # Airport reference
      t.string :airport_ident, null: false # Links to airport via ident (e.g., "YSSY")

      # Runway dimensions
      t.decimal :length_ft
      t.decimal :width_ft
      t.string :surface # e.g., "ASP" (asphalt), "CON" (concrete), "GRS" (grass)
      t.boolean :lighted, default: false
      t.boolean :closed, default: false

      # Low-end runway identifiers and coordinates
      t.string :le_ident # e.g., "16L"
      t.decimal :le_latitude, precision: 9, scale: 6
      t.decimal :le_longitude, precision: 9, scale: 6
      t.decimal :le_elevation_ft
      t.decimal :le_heading_deg
      t.decimal :le_displaced_threshold_ft

      # High-end runway identifiers and coordinates
      t.string :he_ident # e.g., "34R"
      t.decimal :he_latitude, precision: 9, scale: 6
      t.decimal :he_longitude, precision: 9, scale: 6
      t.decimal :he_elevation_ft
      t.decimal :he_heading_deg
      t.decimal :he_displaced_threshold_ft

      # STI and metadata
      t.string :type, null: false # For STI (OurAirportsRunwaySource)
      t.datetime :import_date, null: false
      t.jsonb :data, default: '{}', null: false

      t.timestamps
    end

    # Index for lookups - a runway is uniquely identified by airport + le_ident within a source
    add_index :runway_sources, %i[airport_ident le_ident type],
              name: 'index_runway_sources_on_airport_le_ident_type',
              unique: true
    add_index :runway_sources, :airport_ident
    add_index :runway_sources, :data, using: :gin
  end
end

