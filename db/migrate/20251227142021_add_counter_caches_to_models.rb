# frozen_string_literal: true

class AddCounterCachesToModels < ActiveRecord::Migration[8.0]
  def up
    # Aircraft count on aircraft_types
    add_column :aircraft_types, :aircraft_count, :integer, default: 0, null: false

    # Aircraft types count and aircraft count on manufacturers
    add_column :manufacturers, :aircraft_types_count, :integer, default: 0, null: false
    add_column :manufacturers, :aircraft_count, :integer, default: 0, null: false

    # Aircraft count on operators
    add_column :operators, :aircraft_count, :integer, default: 0, null: false

    # Airports count and operators count on countries
    add_column :countries, :airports_count, :integer, default: 0, null: false
    add_column :countries, :operators_count, :integer, default: 0, null: false

    # Route segments count on routes
    add_column :routes, :route_segments_count, :integer, default: 0, null: false

    # Populate all counter caches
    execute <<-SQL.squish
      UPDATE aircraft_types
      SET aircraft_count = (
        SELECT COUNT(*) FROM aircraft WHERE aircraft.aircraft_type_id = aircraft_types.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE manufacturers
      SET aircraft_types_count = (
        SELECT COUNT(*) FROM aircraft_types WHERE aircraft_types.manufacturer_id = manufacturers.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE manufacturers
      SET aircraft_count = (
        SELECT COUNT(*) FROM aircraft
        INNER JOIN aircraft_types ON aircraft.aircraft_type_id = aircraft_types.id
        WHERE aircraft_types.manufacturer_id = manufacturers.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE operators
      SET aircraft_count = (
        SELECT COUNT(*) FROM aircraft WHERE aircraft.operator_id = operators.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE countries
      SET airports_count = (
        SELECT COUNT(*) FROM airports WHERE airports.country_id = countries.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE countries
      SET operators_count = (
        SELECT COUNT(*) FROM operators WHERE operators.country_id = countries.id
      )
    SQL

    execute <<-SQL.squish
      UPDATE routes
      SET route_segments_count = (
        SELECT COUNT(*) FROM route_segments WHERE route_segments.route_id = routes.id
      )
    SQL
  end

  def down
    remove_column :aircraft_types, :aircraft_count
    remove_column :manufacturers, :aircraft_types_count
    remove_column :manufacturers, :aircraft_count
    remove_column :operators, :aircraft_count
    remove_column :countries, :airports_count
    remove_column :countries, :operators_count
    remove_column :routes, :route_segments_count
  end
end
