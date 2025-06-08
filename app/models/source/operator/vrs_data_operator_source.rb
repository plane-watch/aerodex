# == Schema Information
#
# Table name: operator_sources
#
#  id          :bigint           not null, primary key
#  data        :jsonb            not null
#  iata_code   :string
#  icao_code   :string
#  import_date :datetime         not null
#  name        :string
#  type        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_operator_sources_on_data  (data) USING gin
#
module Source
  module Operator
    class VRSDataOperatorSource < OperatorSource
      include MeiliSearch::Rails

      meilisearch do
        attribute :name
      end
    end
  end
end
