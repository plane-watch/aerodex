# == Schema Information
#
# Table name: source_operators
#
#  id          :bigint           not null, primary key
#  data        :jsonb            not null
#  operator_pk :string           not null
#  source      :string           not null
#  source_date :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_source_operators_on_data  (data) USING gin
#
require "test_helper"

class SourceOperatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
