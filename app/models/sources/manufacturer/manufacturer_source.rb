# == Schema Information
#
# Table name: manufacturer_sources
#
#  id          :bigint           not null, primary key
#  country     :string
#  data        :jsonb            not null
#  icao_code   :string           not null
#  import_date :datetime         not null
#  name        :string           not null
#  type        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

module Sources
  module Manufacturer
    class ManufacturerSource < ApplicationRecord
    end
  end
end