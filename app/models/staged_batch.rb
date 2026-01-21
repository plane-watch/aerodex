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
  # @raise [InvalidStatusError] If batch is not pending
  # @raise [StaleDataError] If any target record was modified after staging
  # @raise [ApplyError] If apply fails
  def apply!(by:)
    raise InvalidStatusError, "Batch must be pending to apply (current: #{status})" unless pending?
    raise ApplyError, "Cannot apply batch with no changes" if staged_changes.empty?

    transaction do
      check_for_stale_data!
      apply_changes!
      update!(
        status: :applied,
        applied_at: Time.current,
        reviewed_by: by,
        reviewed_at: Time.current
      )
    end

    run_post_apply_hooks
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
  # constraints are violated and will be converted to StaleDataError in apply_creates.
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

  # Applies all staged changes to the database.
  def apply_changes!
    # Group changes by record type for efficient bulk operations
    changes_by_type = staged_changes.group_by(&:record_type)

    changes_by_type.each do |record_type, changes|
      model_class = record_type.constantize

      # Note: c.operation returns a string ("create"/"update"), not a symbol
      creates = changes.select { |c| c.operation == "create" }
      updates = changes.select { |c| c.operation == "update" }

      apply_creates(model_class, creates) if creates.any?
      apply_updates(model_class, updates) if updates.any?
    end
  end

  # Applies create operations using insert_all.
  # Converts unique constraint violations into StaleDataError.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The create changes
  # @raise [StaleDataError] If a unique constraint is violated
  def apply_creates(model_class, changes)
    now = Time.current
    records = changes.map do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:created_at] ||= now
      attrs[:updated_at] ||= now
      attrs
    end

    # Normalise all records to have the same keys (insert_all requirement).
    # Different staged changes may have different attributes captured.
    all_keys = records.flat_map(&:keys).uniq
    records = records.map do |record|
      all_keys.each_with_object({}) { |key, hash| hash[key] = record[key] }
    end

    model_class.insert_all(records)
  rescue ActiveRecord::RecordNotUnique => e
    raise StaleDataError, "Record already exists (unique constraint violation): #{e.message}"
  end

  # Applies update operations using individual updates.
  #
  # We don't use upsert_all here because PostgreSQL validates NOT NULL constraints
  # on the INSERT values BEFORE evaluating the ON CONFLICT clause. This means we'd
  # need to provide all non-nullable columns even for updates, which defeats the
  # purpose of partial updates.
  #
  # Instead, we update each record individually using update_columns, which is
  # still efficient and works correctly with partial column sets.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The update changes
  def apply_updates(model_class, changes)
    now = Time.current

    changes.each do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:updated_at] = now

      model_class.where(id: change.record_id).update_all(attrs)
    end
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
