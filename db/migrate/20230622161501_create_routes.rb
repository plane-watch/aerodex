class CreateRoutes < ActiveRecord::Migration[7.0]
  def change
    create_table :routes do |t|
      t.string :call_sign
      t.string :operator_id

      t.timestamps
    end
  end
end
