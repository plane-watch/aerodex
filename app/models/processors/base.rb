# frozen_string_literal: true

module Processors
  class Base
    # A null object that responds to ProgressBar methods but does nothing.
    # Used when running outside of an interactive console.
    class NullProgressBar
      def initialize(*); end
      def increment!; end
      def puts(*); end
      def finish; end
    end

    def self.transform_field(key, value)
      return nil if @transform_data[key].nil?

      {
        key: @transform_data[key][:field] || key,
        value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
      }
    end

    def self.get_source_from_url(url, request_type = 'GET', headers = {})
      mock = true if Rails.env == 'test'

      connection = Excon.new(url, method: request_type, headers: headers, mock: mock)
      result = connection.request

      return unless result.status == 200

      result.body
    end

    def self.new_import_report(import_errors, records_processed)
      Source::SourceImportReport.create(
        import_errors: import_errors,
        importer_type: name,
        records_processed: records_processed,
        success: true
      )
    end

    # Creates a progress bar if running in an interactive console, otherwise returns a null object.
    # This prevents progress bar output during tests and background jobs.
    #
    # @param count [Integer] The total number of items to process
    # @return [ProgressBar, NullProgressBar]
    def self.create_progress_bar(count)
      if interactive_console?
        ProgressBar.new(count)
      else
        NullProgressBar.new(count)
      end
    end

    # Checks if we're running in an interactive console.
    #
    # @return [Boolean] True if running interactively
    def self.interactive_console?
      # Not in test environment
      return false if Rails.env.test?

      # STDOUT must be a TTY (not redirected/piped)
      return false unless $stdout.respond_to?(:tty?) && $stdout.tty?

      # Check if we're in a Rails console or similar
      true
    end

    # Silences ActiveRecord logging during the block execution.
    # This is useful for bulk operations where SQL output would obscure progress bars.
    #
    # @yield The block to execute with silenced logging
    # @return The result of the block
    def self.silence_active_record(&block)
      old_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = nil
      yield
    ensure
      ActiveRecord::Base.logger = old_logger
    end

    # Wraps a block with all bulk import optimisations:
    # - Disables PaperTrail versioning
    # - Deactivates MeiliSearch indexing
    # - Silences ActiveRecord SQL logging
    #
    # Use this for any bulk import or combine operation to improve performance.
    #
    # @yield The block to execute with optimisations enabled
    # @return The result of the block
    def self.with_bulk_import(&block)
      PaperTrail.request(enabled: false) do
        MeiliSearch::Rails.deactivate! do
          silence_active_record(&block)
        end
      end
    end

    # Default batch size for bulk operations
    BATCH_SIZE = 1000

    # Performs batch upserts for a collection of records.
    # Collects records in batches and uses upsert_all for efficiency.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param records [Array<Hash>] Array of attribute hashes to upsert
    # @param unique_by [Symbol, Array] The unique constraint column(s)
    # @param batch_size [Integer] Number of records per batch
    def self.batch_upsert(model_class, records, unique_by:, batch_size: BATCH_SIZE)
      records.each_slice(batch_size) do |batch|
        model_class.upsert_all(batch, unique_by: unique_by, update_only: batch.first.keys - [unique_by].flatten)
      end
    end

    # Finalises a combine operation by reindexing for search and resetting counter caches.
    # Call this at the end of any combine_sources method that uses insert_all/upsert_all.
    #
    # @param model_class [Class] The model class to reindex (e.g., ::Aircraft)
    # @param counter_caches [Hash] Map of parent class to counter column name
    #   e.g., { Operator => :aircraft_count, AircraftType => :aircraft_count }
    # @param includes [Array, Symbol] Associations to preload for reindexing (optional)
    #
    # @example
    #   finalize_combine(
    #     ::Aircraft,
    #     counter_caches: { Operator => :aircraft_count, AircraftType => :aircraft_count }
    #   )
    def self.finalize_combine(model_class, counter_caches: {}, includes: nil)
      # Reindex for search (with optional preloaded associations)
      silence_active_record do
        scope = includes ? model_class.includes(includes) : model_class
        scope.reindex!
      end

      # Reset counter caches (insert_all/upsert_all bypass callbacks)
      reset_counter_caches(model_class, counter_caches) if counter_caches.any?
    end

    # Resets counter caches for the given model's parent associations.
    # Uses raw SQL for efficiency instead of looping through each record.
    #
    # @param model_class [Class] The child model class (e.g., ::Aircraft)
    # @param counter_caches [Hash] Map of parent class to counter column name
    def self.reset_counter_caches(model_class, counter_caches)
      return if counter_caches.empty?

      Rails.logger.info 'Resetting counter caches...'
      child_table = model_class.table_name

      counter_caches.each do |parent_class, counter_column|
        parent_table = parent_class.table_name
        # Infer foreign key from parent class name (Rails convention)
        foreign_key = "#{parent_class.name.demodulize.underscore}_id"

        parent_class.connection.execute(<<~SQL.squish)
          UPDATE #{parent_table}
          SET #{counter_column} = (
            SELECT COUNT(*)
            FROM #{child_table}
            WHERE #{child_table}.#{foreign_key} = #{parent_table}.id
          )
        SQL
      end

      Rails.logger.info 'Counter caches reset.'
    end
  end
end