# frozen_string_literal: true

# Creates the route_sources table for storing raw airline route data from
# external sources before combining into canonical Route and RouteSegment records.
#
# This follows the same single-table-inheritance pattern as operator_sources,
# aircraft_sources, etc. The VRS GitHub importer stores its raw rows here.
class CreateRouteSources < ActiveRecord::Migration[8.0]
  def change
    create_table :route_sources do |t|
      # STI column for the source type (e.g. Source::Route::VRSRouteSource).
      t.string :type, null: false

      # The full normalised callsign, e.g. "QFA1". The natural key for upserts.
      t.string :callsign, null: false

      # The code used to look up the owning airline, e.g. "QFA".
      t.string :airline_code, null: false

      # A hyphen-separated list of airport codes in flight order, e.g. "YSSY-WSSS-EGLL".
      t.string :airport_codes, null: false

      # Flexible storage for source-specific fields (retains VRS Code and Number).
      t.jsonb :data, null: false, default: {}

      # The timestamp of the import batch that produced this record.
      t.datetime :import_date, null: false

      # Exclusion fields (mirrors the other source tables; see HasSourceExclusion).
      t.boolean :excluded, default: false, null: false
      t.string :exclusion_reason
      t.datetime :excluded_at
      t.string :excluded_by

      t.timestamps
    end

    add_index :route_sources, [:callsign, :type], unique: true
    add_index :route_sources, :airline_code
    add_index :route_sources, :excluded
    add_index :route_sources, :data, using: :gin
  end
end
