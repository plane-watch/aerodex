# frozen_string_literal: true

class AddAirportRunwaysCountToAirports < ActiveRecord::Migration[8.0]
  def up
    add_column :airports, :airport_runways_count, :integer, default: 0, null: false

    # Populate existing counts
    execute <<-SQL.squish
      UPDATE airports
      SET airport_runways_count = (
        SELECT COUNT(*)
        FROM airport_runways
        WHERE airport_runways.airport_id = airports.id
      )
    SQL
  end

  def down
    remove_column :airports, :airport_runways_count
  end
end