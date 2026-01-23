# frozen_string_literal: true

# Helper methods for admin functionality.
module AdminHelper
  # Returns the count of pending staged batches.
  #
  # @return [Integer]
  def pending_batches_count
    @pending_batches_count ||= StagedBatch.pending.count
  end
end
