# == Schema Information
#
# Table name: source_import_reports
#
#  id                :integer          not null, primary key
#  importer_type     :string
#  import_errors     :jsonb
#  records_processed :integer
#  success           :boolean
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

module Source
  class SourceImportReport < ApplicationRecord
  end
end
