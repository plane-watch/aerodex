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
