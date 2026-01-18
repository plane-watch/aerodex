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
    failed: 7
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
  #
  # @raise [StaleDataError] If stale data is detected
  def check_for_stale_data!
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

      creates = changes.select(&:operation_create?)
      updates = changes.select(&:operation_update?)

      apply_creates(model_class, creates) if creates.any?
      apply_updates(model_class, updates) if updates.any?
    end
  end

  # Applies create operations using insert_all.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The create changes
  def apply_creates(model_class, changes)
    now = Time.current
    records = changes.map do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:created_at] ||= now
      attrs[:updated_at] ||= now
      attrs
    end

    model_class.insert_all(records)
  end

  # Applies update operations using upsert_all.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The update changes
  def apply_updates(model_class, changes)
    now = Time.current
    records = changes.map do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:id] = change.record_id
      attrs[:updated_at] = now
      attrs
    end

    model_class.upsert_all(records, unique_by: :id)
  end

  # Runs post-apply hooks like reindexing.
  def run_post_apply_hooks
    # Reindex affected models for search
    entity_type.constantize.reindex! if entity_type.constantize.respond_to?(:reindex!)
  rescue NameError
    # Entity type may not be a direct model class
    Rails.logger.warn "Could not reindex #{entity_type} - not a model class"
  end
end
