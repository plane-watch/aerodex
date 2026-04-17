# == Schema Information
#
# Table name: manufacturers
#
#  id                   :integer          not null, primary key
#  aircraft_count       :integer          default(0), not null
#  aircraft_types_count :integer          default(0), not null
#  alt_names            :jsonb
#  country_id           :integer
#  created_at           :datetime         not null
#  field_provenance     :jsonb            default("{}"), not null
#  icao_code            :string
#  last_combined_at     :datetime
#  name                 :string
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_manufacturers_on_country_id  (country_id)
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
