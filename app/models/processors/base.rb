# frozen_string_literal: true

module Processors
  # Base module containing shared functionality for all processors
  module Base
    extend ActiveSupport::Concern

    class_methods do
      def transform_field(key, value)
        return nil if @transform_data[key].nil?

        {
          key: @transform_data[key][:field] || key,
          value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
        }
      end

      def get_source_from_url(url)
        mock = true if Rails.env == 'test'
        result = Excon.get(url, mock: mock)

        return unless result.status == 200

        result.body
      end

      def new_import_report(import_errors, records_processed)
        Source::SourceImportReport.create(import_errors: import_errors, importer_type: name, records_processed: records_processed,
                                  success: true)
      end
    end
  end
end