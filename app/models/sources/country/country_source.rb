# == Schema Information
#
# Table name: country_sources
#
#  id             :bigint           not null, primary key
#  capital        :string
#  data           :jsonb            not null
#  import_date    :datetime         not null
#  iso_2char_code :string
#  iso_3char_code :string
#  iso_num_code   :string
#  name           :string
#  type           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

module Sources
  module Country
    class CountrySource < ApplicationRecord
    end
  end
end
