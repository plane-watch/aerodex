# frozen_string_literal: true

# Adds field_provenance and last_combined_at columns to all canonical tables.
# The field_provenance column stores per-field metadata about the data source and confidence.
#
# Example field_provenance structure:
# {
#   "name": {
#     "source_type": "VRSDataOperatorSource",
#     "source_id": 123,
#     "confidence": 85,
#     "combined_at": "2024-12-24T10:30:00Z"
#   },
#   "icao_code": {
#     "source_type": "OpenTravelOperatorSource",
#     "source_id": 456,
#     "confidence": 70,
#     "combined_at": "2024-12-24T10:30:00Z"
#   }
# }
class AddProvenanceToCanonicalTables < ActiveRecord::Migration[8.0]
  CANONICAL_TABLES = %i[
    operators
    aircraft
    aircraft_types
    manufacturers
    countries
    airports
  ].freeze

  def change
    CANONICAL_TABLES.each do |table_name|
      add_column table_name, :field_provenance, :jsonb, default: {}, null: false
      add_column table_name, :last_combined_at, :datetime
    end
  end
end