# frozen_string_literal: true

require 'test_helper'

class CountriesHelperTest < ActionView::TestCase
  test 'country_flag_path returns the matching flag when the asset exists' do
    country = countries(:united_states)

    assert_equal asset_path('country_flags/us.svg'), country_flag_path(country)
  end

  test 'country_flag_path falls back to the placeholder when no flag asset exists' do
    # "CS" is a formerly-assigned ISO code with no bundled flag (see issue #18).
    country = countries(:serbia_and_montenegro)

    assert_equal asset_path("country_flags/#{CountriesHelper::FALLBACK_FLAG_CODE}.svg"),
                 country_flag_path(country)
  end

  test 'country_flag_path falls back to the placeholder when the code is nil' do
    country = Country.new(iso_2char_code: nil)

    assert_equal asset_path("country_flags/#{CountriesHelper::FALLBACK_FLAG_CODE}.svg"),
                 country_flag_path(country)
  end

  test 'country_flag_path falls back to the placeholder when the country is nil' do
    assert_equal asset_path("country_flags/#{CountriesHelper::FALLBACK_FLAG_CODE}.svg"),
                 country_flag_path(nil)
  end
end
