# == Schema Information
#
# Table name: country_sources
#
#  id               :integer          not null, primary key
#  capital          :string
#  created_at       :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  excluded         :boolean          default(FALSE), not null
#  excluded_at      :datetime
#  excluded_by      :string
#  exclusion_reason :string
#  import_date      :datetime         not null
#  iso_2char_code   :string
#  iso_3char_code   :string
#  iso_num_code     :string
#  name             :string
#  type             :string
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_country_sources_on_excluded  (excluded)
#

# frozen_string_literal: true

module Source
  module Country
    # Country data sourced from OurAirports.com
    #
    # OurAirports provides country data with ISO codes, continent information,
    # and Wikipedia links.
    #
    # @see https://ourairports.com/data/
    class OurAirportsCountrySource < CountrySource
      # Returns the continent code (e.g., "NA", "EU", "AS")
      def continent
        data['continent']
      end

      # Returns the Wikipedia URL for the country
      def wikipedia_link
        data['wikipedia_link']
      end
    end
  end
end
