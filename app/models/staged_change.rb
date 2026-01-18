# frozen_string_literal: true

# Represents an individual record change within a StagedBatch.
#
# Each StagedChange captures the diff for a single record, including:
# - The record type and ID (polymorphic reference)
# - A human-readable identifier (e.g., ICAO code for aircraft)
# - The operation type (create or update)
# - The diff as a hash of field_name => [old_value, new_value]
#
class StagedChange < ApplicationRecord
  # Associations
  belongs_to :staged_batch

  # Enums
  # NOTE: Using prefix: true to avoid conflict with ActiveRecord's create class method.
  # The enum value :create would generate a StagedChange.create scope method that
  # conflicts with AR's built-in create method. This is a justified deviation from
  # the original specification which did not include the prefix option.
  enum :operation, {
    create: 0,
    update: 1
  }, prefix: true

  # Validations
  validates :record_type, presence: true
  validates :record_identifier, presence: true
  validates :operation, presence: true

  # Scopes
  scope :creates, -> { operation_create }
  scope :updates, -> { operation_update }
  scope :for_record, ->(type, id) { where(record_type: type, record_id: id) }

  # Returns the target model class.
  #
  # @return [Class] The ActiveRecord model class
  def record_class
    record_type.constantize
  end

  # Returns the existing record if this is an update.
  #
  # @return [ApplicationRecord, nil] The record or nil for creates
  def record
    return nil if record_id.blank?

    record_class.find_by(id: record_id)
  end

  # Returns the new values from the diff.
  #
  # @return [Hash] Field names mapped to new values
  def new_values
    diff.transform_values(&:last)
  end

  # Returns the old values from the diff.
  #
  # @return [Hash] Field names mapped to old values
  def old_values
    diff.transform_values(&:first)
  end
end
