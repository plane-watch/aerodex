# frozen_string_literal: true

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
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_country_sources_on_excluded  (excluded)
#

module Source
  module Country
    class CountrySource < ApplicationRecord
      include HasSourceExclusion
    end
  end
end
