# frozen_string_literal: true

class CreateAirportSources < ActiveRecord::Migration[8.0]
  def change
    create_table :airport_sources do |t|
      # Identifiers - at least one of icao_code or iata_code should be present
      t.string :icao_code
      t.string :iata_code
      t.string :ident # OurAirports internal identifier (e.g., "YSSY", "00A")

      # Basic info
      t.string :name, null: false
      t.string :city
      t.string :municipality # OurAirports uses municipality, OpenFlights uses city
      t.string :country_code # ISO 2-char code

      # Geographic data
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.decimal :elevation # In feet for OurAirports, metres for OpenFlights
      t.string :timezone

      # Classification
      t.string :airport_type # e.g., "large_airport", "medium_airport", "heliport"

      # STI and metadata
      t.string :type, null: false # For STI (OpenFlightsAirportSource, OurAirportsAirportSource)
      t.datetime :import_date, null: false
      t.jsonb :data, default: '{}', null: false # Store additional source-specific fields

      t.timestamps
    end

    # Index for lookups by identifier and source type
    add_index :airport_sources, %i[icao_code type], name: 'index_airport_sources_on_icao_and_type'
    add_index :airport_sources, %i[iata_code type], name: 'index_airport_sources_on_iata_and_type'
    add_index :airport_sources, %i[ident type], name: 'index_airport_sources_on_ident_and_type'
    add_index :airport_sources, :data, using: :gin
  end
end
