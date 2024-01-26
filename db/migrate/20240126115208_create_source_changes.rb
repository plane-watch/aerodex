class CreateSourceChanges < ActiveRecord::Migration[7.0]
  def change
    create_table :source_changes do |t|
      t.string :type
      t.string :changed

      t.timestamps
    end
  end
end
