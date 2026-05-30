# frozen_string_literal: true

# Adds a unique index on routes (operator_id, call_sign).
#
# A route is uniquely identified by its operator and callsign. This index
# gives routes a natural identity, making combine re-runs idempotent and
# backing the uniqueness validation on the Route model.
class AddUniqueIndexToRoutes < ActiveRecord::Migration[8.0]
  def change
    add_index :routes, [:operator_id, :call_sign],
              unique: true,
              name: 'index_routes_on_operator_id_and_call_sign'
  end
end
