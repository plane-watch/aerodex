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
class StagedBatch < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
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
  scope :actionable, -> { where(status: [:pending, :applied]) }

  # Custom errors
  class InvalidStatusError < StandardError; end
  class StaleDataError < StandardError; end
  class ApplyError < StandardError; end

  # Applies all staged changes to the database.
  #
  # @param by [User, nil] The user approving the batch
  # @raise [InvalidStatusError] If batch is not pending or applying
  # @raise [StaleDataError] If any target record was modified after staging
  # @raise [ApplyError] If apply fails
  def apply!(by:)
    raise InvalidStatusError, "Batch must be pending or applying (current: #{status})" unless pending? || applying?
    raise ApplyError, "Cannot apply batch with no changes" if staged_changes.empty?

    transaction do
      check_for_stale_data!
      apply_changes!

      self.status = :applied
      self.applied_at = Time.current
      self.reviewed_by = by
      self.reviewed_at = Time.current
      self.apply_progress = 100
      save!
    end

    broadcast_completion
    run_post_apply_hooks
  rescue StandardError => e
    # Record the failure (outside transaction so it persists)
    update!(
      status: :failed,
      error_message: "#{e.class}: #{e.message}",
      apply_progress: 0
    )
    broadcast_completion
    raise
  end

  # Rejects the batch, discarding all staged changes.
  #
  # @param by [User, nil] The user rejecting the batch
  # @param reason [String, nil] Optional rejection reason
  def reject!(by:, reason: nil)
    raise InvalidStatusError, "Batch must be pending to reject (current: #{status})" unless pending?

    update!(
      status: :rejected,
      reviewed_by: by,
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
      event: "processing_progress",
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

  # Checks if any target records have been modified since the batch was created.
  # Only checks update operations - create operations will fail naturally if unique
  # constraints are violated during save!.
  #
  # @raise [StaleDataError] If stale data is detected
  def check_for_stale_data!
    # Check updates for external modifications
    staged_changes.updates.find_each do |change|
      record = change.record
      next unless record

      if record.updated_at > created_at
        raise StaleDataError, "Record #{change.record_type}##{change.record_id} " \
                              "was modified after batch was created"
      end
    end
  end

  # Applies all staged changes using standard ActiveRecord.
  def apply_changes!
    staged_changes.find_each.with_index do |change, index|
      apply_single_change(change)
      broadcast_progress_if_needed(index)
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

    if change.operation == "create"
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
    return "" if values.blank?

    # Common identifier fields, in priority order
    identifier_keys = %w[icao_code iata_code code name identifier id slug]

    # Find matching keys from the values
    found_keys = identifier_keys.select { |key| values.key?(key) || values.key?(key.to_sym) }

    # If no common identifiers found, take the first 2 keys
    found_keys = values.keys.first(2).map(&:to_s) if found_keys.empty?

    # Limit to 3 identifiers to keep the message readable
    found_keys.first(3).map { |key|
      value = values[key] || values[key.to_sym]
      "#{key}: #{value}"
    }.join(", ")
  end

  # Minimum percentage change before broadcasting (prevents flooding)
  PROGRESS_BROADCAST_INTERVAL = 1

  # Broadcasts progress if the percentage has changed.
  #
  # @param index [Integer] Current change index (0-based)
  def broadcast_progress_if_needed(index)
    total = apply_total || staged_changes.count
    new_progress = ((index + 1) * 100 / total).to_i

    return if new_progress == apply_progress
    # Only broadcast at intervals, but always broadcast 100%
    return if (new_progress % PROGRESS_BROADCAST_INTERVAL != 0) && new_progress != 100

    update_column(:apply_progress, new_progress)
    broadcast_progress(new_progress)
  end

  # Broadcasts current progress to subscribed clients.
  # Failures are logged but don't interrupt the apply operation.
  #
  # @param progress [Integer] Progress percentage (0-100)
  def broadcast_progress(progress)
    StagedBatchChannel.broadcast_to(self, {
      event: "progress",
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
      event: "complete",
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
    return unless model_class&.respond_to?(:reindex!)

    model_class.reindex!
  rescue StandardError => e
    # Log but don't fail the apply - batch is already committed
    Rails.logger.error "Failed to reindex #{entity_type}: #{e.message}"
    # TODO: Consider adding a 'reindex_failed' flag to the batch
  end
end
