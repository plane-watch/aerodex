class FixAircraftRegistrationCountry < ActiveRecord::Migration[7.1]
  def change
    remove_column :aircraft, :registration_country, :string
    add_reference :aircraft, :registration_country, null: false, foreign_key: { to_table: :countries }
  end
end
