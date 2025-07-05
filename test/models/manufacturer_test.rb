# == Schema Information
#
# Table name: manufacturers
#
#  id         :bigint           not null, primary key
#  alt_names  :jsonb
#  icao_code  :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  country_id :bigint
#
# Indexes
#
#  index_manufacturers_on_country_id  (country_id)
#
# Foreign Keys
#
#  fk_rails_...  (country_id => countries.id)
#
require 'test_helper'

class ManufacturerTest < ActiveSupport::TestCase
  test 'can be associated with a country' do
    country = countries(:united_states)
    manufacturer = manufacturers(:boeing)

    manufacturer.country = country
    assert manufacturer.save
    assert_equal country, manufacturer.country
  end

  test 'can exist without a country' do
    manufacturer = manufacturers(:embraer)
    manufacturer.country = nil

    assert manufacturer.save
    assert_nil manufacturer.country
  end

  test 'can access country attributes' do
    country = countries(:france)
    manufacturer = manufacturers(:airbus)

    manufacturer.country = country
    manufacturer.save

    assert_equal country.name, manufacturer.country.name
    assert_equal country.iso_2char_code, manufacturer.country.iso_2char_code
  end
end
