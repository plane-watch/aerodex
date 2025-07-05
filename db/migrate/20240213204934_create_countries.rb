class CreateCountries < ActiveRecord::Migration[7.1]
  def change
    create_table :countries do |t|
      t.string :iso_2char_code
      t.string :iso_3char_code
      t.string :iso_num_code
      t.string :name
      t.string :capital

      t.timestamps
    end
  end
end
