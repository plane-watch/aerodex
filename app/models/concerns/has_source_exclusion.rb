# frozen_string_literal: true

# Provides the ability to exclude source records from the combine process.
#
# When a source record has incorrect or invalid data, it can be excluded
# rather than deleted. This preserves an audit trail of what was excluded
# and why, while preventing the bad data from polluting canonical models.
#
# @example Excluding a record
#   source = Source::Operator::VRSDataOperatorSource.find(123)
#   source.exclude!(reason: "Incorrect name - should be 'CAA Training Standards'")
#
# @example Re-including a record
#   source.include!
#
# @example Querying only includable records
#   Source::Operator::VRSDataOperatorSource.includable.each { |s| ... }
#
module HasSourceExclusion
  extend ActiveSupport::Concern

  included do
    # Scope to get only records that should be included in combining
    scope :includable, -> { where(excluded: false) }

    # Scope to get only excluded records
    scope :excluded, -> { where(excluded: true) }
  end

  # Excludes this record from the combine process.
  #
  # @param reason [String] The reason for exclusion (required)
  # @param by [String] Who excluded the record (optional)
  # @return [Boolean] True if successful
  #
  # @example
  #   source.exclude!(reason: "Data is incorrect", by: "admin@example.com")
  def exclude!(reason:, by: nil)
    raise ArgumentError, 'Exclusion reason is required' if reason.blank?

    update!(
      excluded: true,
      exclusion_reason: reason,
      excluded_at: Time.current,
      excluded_by: by
    )
  end

  # Re-includes this record in the combine process.
  #
  # @return [Boolean] True if successful
  def include!
    update!(
      excluded: false,
      exclusion_reason: nil,
      excluded_at: nil,
      excluded_by: nil
    )
  end

  # Returns whether this record is excluded from combining.
  #
  # @return [Boolean]
  def excluded?
    excluded
  end

  # Returns whether this record is includable in combining.
  #
  # @return [Boolean]
  def includable?
    !excluded
  end
end
