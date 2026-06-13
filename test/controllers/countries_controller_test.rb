# frozen_string_literal: true

require 'test_helper'

class CountriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  # Regression test for issue #18: a country with a formerly-assigned ISO code
  # (e.g. "CS") has no bundled flag asset, which previously raised
  # Sprockets::AssetNotFound and crashed the index.
  test 'index renders the placeholder flag for a country with no matching flag asset' do
    get countries_path

    assert_response :success
    # Assert the problematic row actually rendered (guards against the test
    # becoming vacuous if the blank-query branch ever stops returning all rows)
    # and that it fell back to the placeholder flag rather than crashing.
    assert_select 'td', text: /Serbia and Montenegro/
    assert_select 'img[src*=?]', "country_flags/#{CountriesHelper::FALLBACK_FLAG_CODE}"
  end

  test 'show renders the placeholder flag for a country with no matching flag asset' do
    get country_path(countries(:serbia_and_montenegro))

    assert_response :success
    assert_select 'img[src*=?]', "country_flags/#{CountriesHelper::FALLBACK_FLAG_CODE}"
  end
end
