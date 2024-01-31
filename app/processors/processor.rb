# frozen_string_literal: true

class Processor
  def self.get_source_from_url(url)
    mock = true if Rails.env == 'test'
    result = Excon.get(url, mock: mock)

    return unless result.status == 200

    result.body
  end

  def self.new_import_report(import_errors, records_processed)
    SourceImportReport.create(import_errors: import_errors, importer_type: name, records_processed: records_processed,
                              success: true)
  end
end
