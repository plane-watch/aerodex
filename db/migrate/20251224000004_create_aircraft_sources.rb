# frozen_string_literal: true

# Creates the aircraft_sources table for storing raw aircraft data from various sources
# before combining into canonical Aircraft records.
#
# This follows the same pattern as operator_sources, manufacturer_sources, etc.
# Each source (CASA, CAANZ, OpenSky) stores its raw data here, which is then
# combined using trust-based field selection.
class CreateAircraftSources < ActiveRecord::Migration[8.0]
  def change
    create_table :aircraft_sources do |t|
      # STI column for source type (CASAAircraftSource, CAANZAircraftSource, etc.)
      t.string :type, null: false

      # Core identifying fields
      t.string :icao, null: false, comment: 'Mode S hex code (24-bit transponder address)'
      t.string :registration, null: false
      t.string :serial_number

      # Aircraft details
      t.string :model
      t.string :type_code, comment: 'ICAO aircraft type designator'
      t.string :manufacturer_code, comment: 'ICAO manufacturer code'

      # Ownership and operation
      t.string :owner
      t.string :operator_name
      t.string :operator_icao

      # Engine details
      t.integer :engine_count
      t.string :engine_model

      # Registration details
      t.date :registration_date
      t.string :registration_country_code, comment: 'ISO 2-char country code'

      # Additional metadata
      t.integer :manufacture_year
      t.string :status

      # Flexible storage for source-specific fields
      t.jsonb :data, null: false, default: {}

      # Import tracking
      t.datetime :import_date, null: false

      t.timestamps
    end

    add_index :aircraft_sources, :icao
    add_index :aircraft_sources, :registration
    add_index :aircraft_sources, :type
    add_index :aircraft_sources, %i[icao type], unique: true
    add_index :aircraft_sources, :data, using: :gin
  end
end
