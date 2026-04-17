# frozen_string_literal: true

# ActionCable channel for real-time batch apply progress updates.
#
# Clients subscribe to a specific batch and receive progress updates
# as the batch is applied.
#
# @example Subscribe from JavaScript
#   consumer.subscriptions.create(
#     { channel: "StagedBatchChannel", id: batchId },
#     { received: (data) => handleMessage(data) }
#   )
#
class StagedBatchChannel < ApplicationCable::Channel
  # Subscribes to progress updates for a specific batch.
  def subscribed
    batch = StagedBatch.find_by(id: params[:id])

    if batch
      stream_for batch
    else
      reject
    end
  end
end
