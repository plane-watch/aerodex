module CountriesHelper
  # The placeholder flag shown when a country has no two-character ISO code,
  # or when no matching flag asset exists on disk. Some formerly-assigned
  # ISO 3166-1 codes (e.g. "CS" for Serbia and Montenegro) have no bundled
  # flag, and Sprockets raises AssetNotFound for a missing asset, which would
  # otherwise crash the page.
  FALLBACK_FLAG_CODE = 'xx'.freeze

  # Resolves the flag asset path for the given country.
  #
  # Falls back to the placeholder flag when the country has no two-character
  # ISO code, or when no matching SVG exists on disk. Mirrors the on-disk
  # lookup used by OperatorsHelper#operator_logo_for.
  #
  # @param country [Country] the country whose flag is required
  # @return [String] the asset path to the flag SVG
  def country_flag_path(country)
    code = country&.iso_2char_code&.downcase
    flag_file = Rails.root.join('app', 'assets', 'images', 'country_flags', "#{code}.svg")
    code = FALLBACK_FLAG_CODE unless code.present? && File.exist?(flag_file)
    asset_path("country_flags/#{code}.svg")
  end
end
