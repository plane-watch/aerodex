# frozen_string_literal: true

require "test_helper"

class StagedBatchChannelTest < ActionCable::Channel::TestCase
  test "subscribes to a batch" do
    batch = StagedBatch.create!(
      processor_type: "Test",
      entity_type: "Test"
    )

    subscribe id: batch.id

    assert subscription.confirmed?
  end

  test "rejects subscription for non-existent batch" do
    subscribe id: "non-existent-uuid"

    assert subscription.rejected?
  end
end
