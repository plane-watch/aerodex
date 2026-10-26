# == Schema Information
#
# Table name: staged_batches
#
#  id                  :uuid             not null, primary key
#  processor_type      :string           not null
#  entity_type         :string           not null
#  status              :integer          default(0), not null
#  summary             :jsonb            default("{}"), not null
#  created_by_id       :integer
#  reviewed_by_id      :integer
#  job_id              :string
#  started_at          :datetime
#  completed_at        :datetime
#  applied_at          :datetime
#  reviewed_at         :datetime
#  notes               :text
#  error_message       :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  apply_progress      :integer          default(0)
#  apply_total         :integer
#  processing_progress :integer          default(0)
#  processing_total    :integer
#
# Indexes
#
#  index_staged_batches_on_created_at      (created_at)
#  index_staged_batches_on_created_by_id   (created_by_id)
#  index_staged_batches_on_entity_type     (entity_type)
#  index_staged_batches_on_job_id          (job_id)
#  index_staged_batches_on_reviewed_by_id  (reviewed_by_id)
#  index_staged_batches_on_status          (status)
#

# frozen_string_literal: true

# Represents a batch of staged changes from a processor run.
#
# A StagedBatch captures all the changes a processor would make, allowing
# review and approval before applying them to the database.
#
# == Statuses
# - processing: Job is currently running
# - pending: Processing complete, awaiting review
# - approved: Reviewed and approved (transitional)
# - applied: Changes have been committed to the database
# - rejected: Batch was rejected, changes discarded
# - superseded: A newer batch replaced this one
# - rolled_back: Applied changes were reversed
# - failed: Processing encountered an error
# - applying: Batch is being applied in a background job
#
# The class length sits above the default limit because a batch's apply/reject
# lifecycle, progress broadcasting and per-change application are one cohesive
# responsibility; splitting them would scatter tightly-coupled logic.
class StagedBatch < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  has_many :staged_changes, dependent: :destroy

  # Enums
  enum :status, {
    processing: 0,
    pending: 1,
    approved: 2,
    applied: 3,
    rejected: 4,
    superseded: 5,
    rolled_back: 6,
    failed: 7,
    applying: 8
  }

  # Validations
  validates :processor_type, presence: true
  validates :entity_type, presence: true

  # Scopes
  scope :for_entity, ->(type) { where(entity_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :actionable, -> { where(status: %i[pending applied]) }

  # Custom errors
  class InvalidStatusError < StandardError; end
  class StaleDataError < StandardError; end
  class ApplyError < StandardError; end

  # Number of staged changes applied per committed transaction.
  APPLY_BATCH_SIZE = 1000

  # Applies the batch's outstanding staged changes in committed chunks.
  #
  # Each chunk of APPLY_BATCH_SIZE changes is applied in its own transaction and
  # committed before the next, so progress is visible to other connections and a
  # failure only rolls back the current chunk. Re-invoking apply! on a failed or
  # in-flight batch resumes over the remaining (applied_at IS NULL) changes; the
  # applied_at marker makes resume idempotent.
  #
  # @param by [User, Integer, nil] The user (or user id) approving the batch
  # @raise [InvalidStatusError] If the batch is not pending, applying or failed
  # @raise [StaleDataError] If an unapplied update target was modified after staging
  # @raise [ApplyError] If the batch has no changes
  # @raise [ActiveRecord::RecordNotFound] If by is an id that matches no user
  def apply!(by:)
    unless pending? || applying? || failed?
      raise InvalidStatusError, "Batch must be pending, applying or failed (current: #{status})"
    end
    raise ApplyError, 'Cannot apply batch with no changes' if staged_changes.empty?

    # Resolve the reviewer up front, before the failure-tracked work below, so
    # invalid input fails fast without applying anything. Resolving (or using
    # it) late would flip a fully-applied batch to failed because the reviewer
    # is only assigned in finish_apply!.
    reviewer = resolve_reviewer(by)

    begin
      start_apply!
      check_for_stale_data!
      apply_changes!
      finish_apply!(reviewer)

      broadcast_completion
      run_post_apply_hooks
    rescue StandardError => e
      mark_failed!(e)
      broadcast_completion
      raise
    end
  end

  # Rejects the batch, discarding all staged changes.
  #
  # @param by [User, Integer, nil] The user (or user id) rejecting the batch
  # @param reason [String, nil] Optional rejection reason
  def reject!(by:, reason: nil)
    raise InvalidStatusError, "Batch must be pending to reject (current: #{status})" unless pending?

    update!(
      status: :rejected,
      reviewed_by: resolve_reviewer(by),
      reviewed_at: Time.current,
      notes: reason
    )
  end

  # Broadcasts processing progress to subscribed clients.
  # Failures are logged but don't interrupt the processing operation.
  #
  # @param progress [Integer] Progress percentage (0-100)
  def broadcast_processing_progress(progress)
    update_column(:processing_progress, progress)
    StagedBatchChannel.broadcast_to(self, {
                                      event: 'processing_progress',
                                      progress: progress,
                                      status: status
                                    })
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast processing progress for batch #{id}: #{e.message}"
  end

  # Broadcasts processing progress if the percentage has changed.
  # Throttles broadcasts to avoid flooding clients.
  #
  # @param current [Integer] Current item index (0-based)
  # @param total [Integer] Total number of items
  def broadcast_processing_progress_if_needed(current, total)
    return if total.zero?

    new_progress = ((current.to_f / total) * 100).round
    return if new_progress == processing_progress
    return if (new_progress % PROGRESS_BROADCAST_INTERVAL != 0) && new_progress != 100

    broadcast_processing_progress(new_progress)
  end

  private

  # Checks whether any unapplied UPDATE target has been modified since the batch
  # was created. Creates are not checked - they fail naturally on unique
  # constraint violations during save!.
  #
  # @raise [StaleDataError] If stale data is detected
  def check_for_stale_data!
    staged_changes.updates.where(applied_at: nil).find_each do |change|
      record = change.record
      next unless record

      if record.updated_at > created_at
        raise StaleDataError, "Record #{change.record_type}##{change.record_id} " \
                              'was modified after batch was created'
      end
    end
  end

  # Applies the outstanding changes in committed chunks, advancing progress
  # after each chunk commits.
  def apply_changes!
    total = apply_total || staged_changes.count
    applied = staged_changes.where.not(applied_at: nil).count

    staged_changes.where(applied_at: nil).order(:id).find_in_batches(batch_size: apply_batch_size) do |chunk|
      transaction do
        chunk.each { |change| apply_single_change(change) }
      end
      applied += chunk.size
      update_apply_progress(applied, total)
    end
  end

  # Applies a single staged change using save!/update! and records its
  # completion by setting applied_at. The applied_at write happens within
  # whatever transaction surrounds the call (the chunk transaction in
  # apply_changes!), so a record and its marker always commit together.
  #
  # @param change [StagedChange] The change to apply
  # @raise [ActiveRecord::RecordInvalid] Re-raised with enriched context about the failing record
  def apply_single_change(change)
    model_class = change.record_type.constantize

    if change.operation == 'create'
      record = model_class.new(change.new_values)
      record.save!
    else
      record = model_class.find(change.record_id)
      record.update!(change.new_values)
    end

    change.update_column(:applied_at, Time.current)
  rescue ActiveRecord::RecordInvalid => e
    # Enrich the error with context about which record failed
    context = build_change_context(change)
    raise ActiveRecord::RecordInvalid.new(e.record), "#{context}: #{e.message}", e.backtrace
  end

  # Builds a human-readable context string for a staged change.
  #
  # @param change [StagedChange] The change to describe
  # @return [String] A description like "Create Operator (icao_code: AYD, name: Example)"
  def build_change_context(change)
    operation = change.operation.capitalize
    record_type = change.record_type.demodulize

    # Pick the most identifying attributes from the new values
    identifiers = extract_identifiers(change.new_values)

    if identifiers.present?
      "#{operation} #{record_type} (#{identifiers})"
    else
      "#{operation} #{record_type}"
    end
  end

  # Extracts the most identifying attributes from a hash of values.
  # Prioritises common identifier fields, then falls back to the first few values.
  #
  # @param values [Hash] The attribute values
  # @return [String] Formatted key-value pairs like "icao_code: AYD, name: Example"
  def extract_identifiers(values)
    return '' if values.blank?

    # Common identifier fields, in priority order
    identifier_keys = %w[icao_code iata_code code name identifier id slug]

    # Find matching keys from the values
    found_keys = identifier_keys.select { |key| values.key?(key) || values.key?(key.to_sym) }

    # If no common identifiers found, take the first 2 keys
    found_keys = values.keys.first(2).map(&:to_s) if found_keys.empty?

    # Limit to 3 identifiers to keep the message readable
    found_keys.first(3).map do |key|
      value = values[key] || values[key.to_sym]
      "#{key}: #{value}"
    end.join(', ')
  end

  # Minimum percentage change before broadcasting (prevents flooding)
  PROGRESS_BROADCAST_INTERVAL = 1

  # Persists and broadcasts apply progress. The update_column is its own
  # committed write (outside any chunk transaction), so other connections see it.
  #
  # @param applied [Integer] Number of changes applied so far
  # @param total [Integer] Total changes in the batch
  def update_apply_progress(applied, total)
    new_progress = total.zero? ? 100 : (applied * 100 / total)
    return if new_progress == apply_progress

    update_column(:apply_progress, new_progress)
    broadcast_progress(new_progress)
  end

  # Moves the batch into the applying state, fixing the total once and seeding
  # progress from any already-applied changes (for resume). Committed immediately.
  def start_apply!
    update!(
      status: :applying,
      apply_total: staged_changes.count,
      apply_progress: current_apply_percentage
    )
    broadcast_progress(apply_progress)
  end

  # Finalises a fully-applied batch.
  #
  # @param reviewer [User, nil] The approving user (already resolved)
  def finish_apply!(reviewer)
    update!(
      status: :applied,
      applied_at: Time.current,
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      apply_progress: 100
    )
  end

  # Resolves the reviewer argument to a User (or nil). Accepts a User instance,
  # a user id, or nil, so the method is convenient to call from a console or a
  # background job. Raises ActiveRecord::RecordNotFound for an unknown id.
  #
  # @param by [User, Integer, String, nil]
  # @return [User, nil]
  def resolve_reviewer(by)
    return by if by.nil? || by.is_a?(User)

    User.find(by)
  end

  # Records a failure while retaining the committed apply_progress so the UI
  # shows true partial progress and the batch can be resumed.
  #
  # @param error [StandardError] The failure
  def mark_failed!(error)
    update!(status: :failed, error_message: "#{error.class}: #{error.message}")
  end

  # The percentage of changes already applied (used to seed progress on resume).
  #
  # @return [Integer]
  def current_apply_percentage
    total = staged_changes.count
    return 0 if total.zero?

    staged_changes.where.not(applied_at: nil).count * 100 / total
  end

  # The chunk size for apply transactions. Extracted so tests can shrink it.
  #
  # @return [Integer]
  def apply_batch_size
    APPLY_BATCH_SIZE
  end

  # Broadcasts current progress to subscribed clients.
  # Failures are logged but don't interrupt the apply operation.
  #
  # @param progress [Integer] Progress percentage (0-100)
  def broadcast_progress(progress)
    StagedBatchChannel.broadcast_to(self, {
                                      event: 'progress',
                                      progress: progress,
                                      status: status
                                    })
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast progress for batch #{id}: #{e.message}"
  end

  # Broadcasts completion (success or failure) to subscribed clients.
  # Failures are logged but don't interrupt the apply operation.
  def broadcast_completion
    StagedBatchChannel.broadcast_to(self, {
                                      event: 'complete',
                                      status: status,
                                      error_message: error_message
                                    })
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast completion for batch #{id}: #{e.message}"
  end

  # Runs post-apply hooks like reindexing.
  def run_post_apply_hooks
    # Reindex affected models for search
    model_class = entity_type.safe_constantize
    return unless model_class.respond_to?(:reindex!)

    model_class.reindex!
  rescue StandardError => e
    # Log but don't fail the apply - batch is already committed
    Rails.logger.error "Failed to reindex #{entity_type}: #{e.message}"
    # TODO: Consider adding a 'reindex_failed' flag to the batch
  end
end
