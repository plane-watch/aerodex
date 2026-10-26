# frozen_string_literal: true

require 'test_helper'

class EnrichmentCountrySerializerTest < ActiveSupport::TestCase
  test 'serialises a country to the v2 shape' do
    country = countries(:australia)
    result = Enrichment::CountrySerializer.call(country)

    # Expected values are derived from the record so the test asserts the
    # field-to-column mapping rather than fixture data (the YAML fixture loader
    # mangles some literals, e.g. an unquoted `036` is parsed as octal).
    assert_equal(
      {
        name: country.name,
        iso_2char_code: country.iso_2char_code,
        iso_3char_code: country.iso_3char_code,
        iso_num_code: country.iso_num_code,
        capital: country.capital
      },
      result
    )
    assert_equal 'Australia', result[:name]
    assert_equal 'AU', result[:iso_2char_code]
  end

  test 'returns nil for a nil country' do
    assert_nil Enrichment::CountrySerializer.call(nil)
  end
end
