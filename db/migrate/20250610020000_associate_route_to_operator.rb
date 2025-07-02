class AssociateRouteToOperator < ActiveRecord::Migration[7.1]
  def change
    remove_column :routes, :operator_id, :string
    add_reference :routes, :operator, null: false, foreign_key: true
  end
end
