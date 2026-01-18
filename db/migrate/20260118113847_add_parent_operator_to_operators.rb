class AddParentOperatorToOperators < ActiveRecord::Migration[8.0]
  def change
    add_column :operators, :parent_operator_id, :bigint, null: true
    add_foreign_key :operators, :operators, column: :parent_operator_id
    add_index :operators, :parent_operator_id
  end
end
