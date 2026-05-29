# frozen_string_literal: true

module Enrichment
  # Serialises a Country into the shared `country` object used throughout the
  # v2 enrichment contract. Returns nil when no country is present so callers
  # can embed the result directly.
  class CountrySerializer
    # @param country [Country, nil]
    # @return [Hash, nil]
    def self.call(country)
      return nil if country.nil?

      {
        name: country.name,
        iso_2char_code: country.iso_2char_code,
        iso_3char_code: country.iso_3char_code,
        iso_num_code: country.iso_num_code,
        capital: country.capital
      }
    end
  end
end
