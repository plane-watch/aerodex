class CreateCountrySources < ActiveRecord::Migration[7.1]
  def change
    create_table :country_sources do |t|
      t.string :iso_2char_code
      t.string :iso_3char_code
      t.string :iso_num_code
      t.string :name
      t.string :capital
      t.string :type
      t.datetime :import_date, null: false
      t.jsonb  :data, null: false, default: '{}'

      t.timestamps
    end
  end
end
