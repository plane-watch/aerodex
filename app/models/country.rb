# == Schema Information
#
# Table name: countries
#
#  id             :bigint           not null, primary key
#  capital        :string
#  iso_2char_code :string
#  iso_3char_code :string
#  iso_num_code   :string
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Country < ApplicationRecord
end
