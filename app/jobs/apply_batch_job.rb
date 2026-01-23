# frozen_string_literal: true

# Background job for applying staged batches.
#
# Applies all staged changes in a transaction. On success, updates
# the batch status to applied. On failure, rolls back changes and
# marks the batch as failed.
#
# @example Enqueue a batch to be applied
#   ApplyBatchJob.perform_later(batch.id, user_id: current_user.id)
#
class ApplyBatchJob < ApplicationJob
  queue_as :default

  # Applies the staged batch.
  #
  # @param batch_id [String] The UUID of the batch to apply
  # @param user_id [Integer, nil] The ID of the user who approved the batch
  def perform(batch_id, user_id:)
    batch = StagedBatch.find(batch_id)
    user = user_id ? User.find(user_id) : nil

    batch.apply!(by: user)
  end
end
