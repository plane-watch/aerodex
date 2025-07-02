class AddCountryToOperator < ActiveRecord::Migration[7.1]
  def change
    add_reference :operators, :country, null: true, foreign_key: true
  end
end
