# == Schema Information
#
# Table name: manufacturer_sources
#
#  id          :bigint           not null, primary key
#  alt_names   :jsonb
#  country     :string
#  data        :jsonb            not null
#  icao_code   :string           not null
#  import_date :datetime         not null
#  name        :string           not null
#  type        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

module Source
  module Manufacturer
    class OpenskyManufacturerSource < ManufacturerSource
    end
  end
end
