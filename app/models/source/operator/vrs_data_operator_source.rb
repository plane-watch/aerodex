# == Schema Information
#
# Table name: operator_sources
#
#  id               :integer          not null, primary key
#  created_at       :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  excluded         :boolean          default(FALSE), not null
#  excluded_at      :datetime
#  excluded_by      :string
#  exclusion_reason :string
#  iata_code        :string
#  icao_code        :string
#  import_date      :datetime         not null
#  name             :string
#  type             :string           not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_operator_sources_on_data      (data)
#  index_operator_sources_on_excluded  (excluded)
#

module Source
  module Operator
    class VRSDataOperatorSource < OperatorSource
      meilisearch do
        attribute :name
      end
    end
  end
end
