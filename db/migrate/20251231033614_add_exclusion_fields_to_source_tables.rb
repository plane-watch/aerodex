# frozen_string_literal: true

# Adds exclusion fields to all source tables.
#
# This allows source records to be flagged as excluded from the combine process
# without deleting them, preserving an audit trail of what was excluded and why.
class AddExclusionFieldsToSourceTables < ActiveRecord::Migration[8.0]
  SOURCE_TABLES = %i[
    country_sources
    manufacturer_sources
    operator_sources
    aircraft_sources
    airport_sources
    runway_sources
    aircraft_type_sources
  ].freeze

  def change
    SOURCE_TABLES.each do |table|
      change_table table do |t|
        t.boolean :excluded, default: false, null: false
        t.string :exclusion_reason
        t.datetime :excluded_at
        t.string :excluded_by
      end

      add_index table, :excluded
    end
  end
end
