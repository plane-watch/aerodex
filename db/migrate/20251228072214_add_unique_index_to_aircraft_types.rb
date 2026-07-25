# Adds a unique index on (type_code, name) to support variant-level aircraft types.
#
# Previously, type_code was effectively unique (one AircraftType per ICAO designator).
# Now we support multiple variants per type_code, e.g.:
#   - AC95: "695 Jetprop Commander 980"
#   - AC95: "695 Jetprop Commander 1000"
#
# The unique constraint ensures each variant is only recorded once.
class AddUniqueIndexToAircraftTypes < ActiveRecord::Migration[8.0]
  def change
    add_index :aircraft_types, %i[type_code name], unique: true, name: 'index_aircraft_types_on_type_code_and_name'
  end
end
