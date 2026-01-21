# == Schema Information
#
# Table name: staged_batches
#
#  id             :uuid             not null, primary key
#  processor_type :string           not null
#  entity_type    :string           not null
#  status         :integer          default(0), not null
#  summary        :jsonb            default("{}"), not null
#  created_by_id  :integer
#  reviewed_by_id :integer
#  job_id         :string
#  started_at     :datetime
#  completed_at   :datetime
#  applied_at     :datetime
#  reviewed_at    :datetime
#  notes          :text
#  error_message  :text
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  apply_progress :integer          default(0)
#  apply_total    :integer
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

    run_post_apply_hooks
  rescue StandardError => e
    # Record the failure (outside transaction so it persists)
    update!(
      status: :failed,
      error_message: "#{e.class}: #{e.message}",
      apply_progress: 0
    )
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
      update_apply_progress(index)
    end
  end

  # Applies a single staged change using save!/update!
  #
  # @param change [StagedChange] The change to apply
  def apply_single_change(change)
    model_class = change.record_type.constantize

    if change.operation == "create"
      record = model_class.new(change.new_values)
      record.save!
    else
      record = model_class.find(change.record_id)
      record.update!(change.new_values)
    end
  end

  # Updates apply progress percentage.
  #
  # @param index [Integer] Current change index (0-based)
  def update_apply_progress(index)
    total = apply_total || staged_changes.count
    new_progress = ((index + 1) * 100 / total).to_i
    return if new_progress == apply_progress

    update_column(:apply_progress, new_progress)
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
