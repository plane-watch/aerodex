require "test_helper"

class CountriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  # Regression test for issue #18: a country with a formerly-assigned ISO code
  # (e.g. "CS") has no bundled flag asset, which previously raised
  # Sprockets::AssetNotFound and crashed the index.
  test "index renders when a country has no matching flag asset" do
    get countries_path

    assert_response :success
  end

  test "show renders when the country has no matching flag asset" do
    get country_path(countries(:serbia_and_montenegro))

    assert_response :success
  end
end
