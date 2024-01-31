# == Schema Information
#
# Table name: source_import_reports
#
#  id                :bigint           not null, primary key
#  import_errors     :jsonb
#  importer_type     :string
#  records_processed :integer
#  success           :boolean
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
require "test_helper"

class SourceImportReportTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
