# == Schema Information
#
# Table name: country_sources
#
#  id               :integer          not null, primary key
#  iso_2char_code   :string
#  iso_3char_code   :string
#  iso_num_code     :string
#  name             :string
#  capital          :string
#  type             :string
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  excluded         :boolean          default("false"), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_country_sources_on_excluded  (excluded)
#

# frozen_string_literal: true

module Source
  module Country
    # Country data sourced from OpenFlights.org
    #
    # OpenFlights provides country data with ISO codes and DAFIF codes.
    # DAFIF (Digital Aeronautical Flight Information File) codes are used
    # by military and some aviation systems.
    #
    # @see https://openflights.org/data
    class OpenFlightsCountrySource < CountrySource
      # Returns the DAFIF code (military aviation code)
      def dafif_code
        data['dafif_code']
      end
    end
  end
end
