# == Schema Information
#
# Table name: operator_sources
#
#  id               :integer          not null, primary key
#  icao_code        :string
#  iata_code        :string
#  name             :string
#  type             :string           not null
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_operator_sources_on_data      (data)
#  index_operator_sources_on_excluded  (excluded)
#

module Source
  module Operator
    class OpenTravelOperatorSource < OperatorSource
      meilisearch do
        attribute :name
      end
    end
  end
end
