# frozen_string_literal: true

require "test_helper"

class ProcessorBaseStagingTest < ActiveSupport::TestCase
  # Test processor that uses staging
  class TestProcessor < Processors::Base
    def self.combine_sources(triggered_by: nil)
      with_staged_batch(entity_type: "Country", triggered_by: triggered_by) do
        # Simulate processing a country
        country = Country.new(
          name: "Test Country",
          iso_2char_code: "TC",
          iso_3char_code: "TST"
        )

        stage_change(
          country,
          operation: :create,
          identifier: "TC"
        )
      end
    end
  end

  test "with_staged_batch creates a batch record" do
    assert_difference "StagedBatch.count", 1 do
      TestProcessor.combine_sources
    end
  end

  test "with_staged_batch sets processor_type" do
    batch = TestProcessor.combine_sources
    assert_equal "ProcessorBaseStagingTest::TestProcessor", batch.processor_type
  end

  test "with_staged_batch sets entity_type" do
    batch = TestProcessor.combine_sources
    assert_equal "Country", batch.entity_type
  end

  test "with_staged_batch starts in processing status" do
    # We need to check during the block, so use a flag
    status_during_block = nil

    Processors::Base.class_eval do
      define_singleton_method(:test_with_staged_batch) do
        with_staged_batch(entity_type: "Test", triggered_by: nil) do
          status_during_block = current_batch.status
        end
      end
    end

    Processors::Base.test_with_staged_batch
    assert_equal "processing", status_during_block
  end

  test "with_staged_batch transitions to pending on success" do
    batch = TestProcessor.combine_sources
    assert_equal "pending", batch.status
  end

  test "stage_change creates a StagedChange record" do
    assert_difference "StagedChange.count", 1 do
      TestProcessor.combine_sources
    end
  end

  test "stage_change captures diff for new records" do
    batch = TestProcessor.combine_sources
    change = batch.staged_changes.first

    assert_equal "create", change.operation
    assert_equal "TC", change.record_identifier
    assert_includes change.diff.keys, "name"
    assert_equal [nil, "Test Country"], change.diff["name"]
  end

  test "summary is persisted with counts" do
    batch = TestProcessor.combine_sources
    batch.reload # Verify the summary was actually persisted to the database
    assert_equal 1, batch.summary["created"]
    assert_equal 0, batch.summary["updated"]
  end
end
