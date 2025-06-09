# frozen_string_literal: true
module Processor
  class Base
    def self.transform_field(key, value)
      return nil if @transform_data[key].nil?

      {
        key: @transform_data[key][:field] || key,
        value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
      }
    end
    def self.get_source_from_url(url)
      mock = true if Rails.env == 'test'
      result = Excon.get(url, mock: mock)

      return unless result.status == 200

      result.body
    end

    def self.new_import_report(import_errors, records_processed)
      Source::SourceImportReport.create(import_errors: import_errors, importer_type: name, records_processed: records_processed,
                                success: true)
    end
  end
end

