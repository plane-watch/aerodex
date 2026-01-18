# == Schema Information
#
# Table name: manufacturer_sources
#
#  id               :integer          not null, primary key
#  name             :string           not null
#  icao_code        :string           not null
#  type             :string           not null
#  country          :string
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  alt_names        :jsonb
#  excluded         :boolean          default("false"), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_manufacturer_sources_on_excluded  (excluded)
#

module Source
  module Manufacturer
    class CfappsICAOIntManufacturerSource < ManufacturerSource
    end
  end
end
