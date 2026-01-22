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

    # =========================================================================
    # Staged Batch Methods
    # =========================================================================

    # Thread-local storage for the current batch during processing.
    #
    # @return [StagedBatch, nil] The current batch or nil if not in a batch
    def self.current_batch
      Thread.current[:processor_current_batch]
    end

    # Sets the current batch in thread-local storage.
    #
    # @param batch [StagedBatch, nil] The batch to set
    def self.current_batch=(batch)
      Thread.current[:processor_current_batch] = batch
    end

    # Thread-local storage for staged records cache during processing.
    # Structure: { ModelClass => { field_name => { downcased_value => record } } }
    #
    # @return [Hash, nil] The cache or nil if not in a batch
    def self.staged_records_cache
      Thread.current[:processor_staged_records_cache]
    end

    # Sets the staged records cache in thread-local storage.
    #
    # @param cache [Hash, nil] The cache to set
    def self.staged_records_cache=(cache)
      Thread.current[:processor_staged_records_cache] = cache
    end

    # Declares which fields to index for staged record lookups.
    #
    # Call at the start of processing to specify which fields should be
    # indexed for fast lookups. Only indexed fields can be used with
    # find_staged_or_persisted.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param fields [Array<Symbol>] The field names to index
    #
    # @example
    #   index_staged_records_by(Operator, :icao_code, :name)
    def self.index_staged_records_by(model_class, *fields)
      staged_records_cache[model_class] ||= {}
      fields.each do |field|
        staged_records_cache[model_class][field] ||= {}
      end
    end

    # Caches a staged record for subsequent lookups within the batch.
    #
    # Indexes the record by all declared fields (via index_staged_records_by).
    # Uses case-insensitive keys for string values.
    #
    # @param record [ApplicationRecord] The record to cache
    def self.cache_staged_record(record)
      model_cache = staged_records_cache[record.class]
      return unless model_cache

      model_cache.each_key do |field|
        value = record.public_send(field)
        next if value.blank?

        key = value.to_s.downcase
        model_cache[field][key] = record
      end
    end

    # Looks up a record in the staged cache only.
    #
    # Searches by the provided criteria fields. Returns the first match found.
    # Uses case-insensitive matching for string values.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param criteria [Hash] Field/value pairs to search by
    # @return [ApplicationRecord, nil] The cached record or nil
    #
    # @example Single value lookup
    #   find_in_staged_cache(Operator, icao_code: "QFA")
    #
    # @example Array of values (returns first match)
    #   find_in_staged_cache(Operator, icao_code: ["QFA", "JST"])
    def self.find_in_staged_cache(model_class, **criteria)
      model_cache = staged_records_cache[model_class]
      return nil unless model_cache

      criteria.each do |field, value|
        next unless model_cache[field]

        values = Array(value)
        values.each do |v|
          key = v.to_s.downcase
          record = model_cache[field][key]
          return record if record
        end
      end

      nil
    end

    # Looks up a record in the staged cache first, then falls back to the database.
    #
    # This is the primary lookup method for processors during batch processing.
    # It ensures that recently staged records can be found even though they
    # haven't been persisted yet.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param criteria [Hash] Field/value pairs to search by
    # @return [ApplicationRecord, nil] The record or nil
    #
    # @example
    #   find_staged_or_persisted(Operator, icao_code: "QFA")
    #   find_staged_or_persisted(Operator, icao_code: ["QFA", "JST"])
    def self.find_staged_or_persisted(model_class, **criteria)
      # Check staged cache first
      record = find_in_staged_cache(model_class, **criteria)
      return record if record

      # Fall back to database
      model_class.find_by(**criteria)
    end

    # Wraps a processor run with staged batch tracking.
    #
    # Creates a StagedBatch at the start, yields to the processing block,
    # and finalises the batch status and summary on completion.
    #
    # @param entity_type [String] The entity type being processed (e.g., "Aircraft")
    # @param triggered_by [User, nil] The user who triggered the run
    # @yield The processing block
    # @return [StagedBatch] The completed batch
    def self.with_staged_batch(entity_type:, triggered_by: nil)
      check_pending_batch!(entity_type)

      self.current_batch = StagedBatch.create!(
        processor_type: name,
        entity_type: entity_type,
        status: :processing,
        created_by: triggered_by,
        started_at: Time.current,
        summary: { "created" => 0, "updated" => 0, "unchanged" => 0 }
      )
      self.staged_records_cache = {}

      yield

      current_batch.update!(
        status: :pending,
        completed_at: Time.current,
        summary: current_batch.summary
      )

      current_batch
    rescue StandardError => e
      if current_batch&.persisted?
        current_batch.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: "#{e.class}: #{e.message}"
        )
      end
      raise
    ensure
      self.current_batch = nil
      self.staged_records_cache = nil
    end

    # Stages a change for a record.
    #
    # Captures the diff of the record's changes and stores it in the current
    # batch for later review and approval.
    #
    # @param record [ApplicationRecord] The record being changed
    # @param operation [Symbol] :create or :update
    # @param identifier [String] Human-readable identifier for the record
    # @raise [RuntimeError] If called outside of a with_staged_batch block
    # @raise [ArgumentError] If an unknown operation is specified
    def self.stage_change(record, operation:, identifier:)
      raise "No current batch - call within with_staged_batch block" unless current_batch

      diff = case operation
             when :create
               # For creates, all non-nil attributes are "new"
               record.attributes.compact.transform_values { |v| [nil, v] }
             when :update
               # For updates, use ActiveRecord's changes hash
               record.changes.transform_values { |old_new| old_new }
             else
               raise ArgumentError, "Unknown operation: #{operation}"
             end

      current_batch.staged_changes.create!(
        record_type: record.class.name,
        record_id: record.id,
        record_identifier: identifier,
        operation: operation,
        diff: diff
      )

      # Cache the record for subsequent lookups within this batch
      cache_staged_record(record)

      # Update summary counts
      key = operation == :create ? "created" : "updated"
      current_batch.summary[key] += 1
    end

    # Checks for pending batches and handles according to configuration.
    #
    # Currently blocks processing if a pending batch exists for the same
    # entity type to prevent conflicting changes.
    #
    # @param entity_type [String] The entity type to check
    # @raise [RuntimeError] If a pending batch exists
    def self.check_pending_batch!(entity_type)
      pending = StagedBatch.pending.where(entity_type: entity_type).first
      return unless pending

      # For now, we block. TODO: Make this configurable (block vs supersede)
      raise "Pending batch exists for #{entity_type} (ID: #{pending.id}). " \
            "Approve or reject it before running again."
    end
  end
end