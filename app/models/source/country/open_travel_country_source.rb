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

module Source
  module Country
    class OpenTravelCountrySource < CountrySource
    end
  end
end
