# == Schema Information
#
# Table name: manufacturer_sources
#
#  id               :integer          not null, primary key
#  alt_names        :jsonb
#  country          :string
#  created_at       :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  excluded         :boolean          default(FALSE), not null
#  excluded_at      :datetime
#  excluded_by      :string
#  exclusion_reason :string
#  icao_code        :string           not null
#  import_date      :datetime         not null
#  name             :string           not null
#  type             :string           not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_manufacturer_sources_on_excluded  (excluded)
#

module Source
  module Manufacturer
    class OpenskyManufacturerSource < ManufacturerSource
    end
  end
end
