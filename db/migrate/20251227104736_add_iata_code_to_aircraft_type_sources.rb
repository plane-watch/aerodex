# frozen_string_literal: true

class AddIataCodeToAircraftTypeSources < ActiveRecord::Migration[8.0]
  def change
    add_column :aircraft_type_sources, :iata_code, :string
    add_index :aircraft_type_sources, %i[iata_code type], name: 'index_aircraft_type_sources_on_iata_and_type'
  end
end
