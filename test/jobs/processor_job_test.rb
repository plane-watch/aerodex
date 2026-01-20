# frozen_string_literal: true

require "test_helper"

class ProcessorJobTest < ActiveJob::TestCase
  # We test this with a mock processor since real processors
  # require database fixtures

  class MockProcessor
    def self.combine_sources(triggered_by: nil)
      StagedBatch.create!(
        processor_type: name,
        entity_type: "Mock",
        status: :pending
      )
    end
  end

  def setup
    @stubbed_constants = []
  end

  def teardown
    # Clean up any constants we stubbed
    @stubbed_constants.each do |name|
      parts = name.split("::")
      parent = parts[0..-2].inject(Object) { |mod, part| mod.const_get(part) }
      parent.send(:remove_const, parts.last) if parent.const_defined?(parts.last, false)
    end
  end

  test "perform creates a staged batch" do
    # Register the mock processor
    stub_const("Processors::Mock::Mock", MockProcessor)

    assert_difference "StagedBatch.count", 1 do
      ProcessorJob.perform_now("Processors::Mock::Mock")
    end
  end

  test "perform sets job_id on the batch" do
    stub_const("Processors::Mock::Mock", MockProcessor)

    job = ProcessorJob.new("Processors::Mock::Mock")
    job.perform_now

    batch = StagedBatch.last
    assert_equal job.job_id, batch.job_id
  end

  test "perform marks batch as failed when processor raises error" do
    failing_processor = Class.new do
      def self.combine_sources(triggered_by: nil)
        batch = StagedBatch.create!(
          processor_type: name,
          entity_type: "Mock",
          status: :pending
        )
        raise StandardError, "Processing failed"
      end

      def self.name
        "ProcessorJobTest::FailingProcessor"
      end
    end

    stub_const("ProcessorJobTest::FailingProcessor", failing_processor)

    # Should mark batch as failed AND re-raise
    assert_raises(StandardError) do
      ProcessorJob.perform_now("ProcessorJobTest::FailingProcessor")
    end

    batch = StagedBatch.last
    assert_equal "failed", batch.status
    assert_includes batch.error_message, "StandardError: Processing failed"
  end

  test "perform re-raises when processor class cannot be loaded" do
    assert_raises(NameError) do
      ProcessorJob.perform_now("NonExistent::Processor")
    end

    # Should not create any batches
    assert_equal 0, StagedBatch.count
  end

  test "error message includes backtrace" do
    failing_processor = Class.new do
      def self.combine_sources(triggered_by: nil)
        batch = StagedBatch.create!(
          processor_type: name,
          entity_type: "Mock",
          status: :pending
        )
        raise StandardError, "Test error"
      end

      def self.name
        "ProcessorJobTest::BacktraceProcessor"
      end
    end

    stub_const("ProcessorJobTest::BacktraceProcessor", failing_processor)

    # Should mark batch as failed AND re-raise
    assert_raises(StandardError) do
      ProcessorJob.perform_now("ProcessorJobTest::BacktraceProcessor")
    end

    batch = StagedBatch.last
    assert_includes batch.error_message, "StandardError: Test error"
    # Error message should include file paths from backtrace
    assert_match(/\.rb:\d+/, batch.error_message)
  end

  private

  def stub_const(name, value)
    parts = name.split("::")

    # Build parent module hierarchy
    parent = parts[0..-2].inject(Object) do |mod, part|
      begin
        mod.const_get(part)
      rescue NameError
        mod.const_set(part, Module.new)
      end
    end

    # Set the constant
    unless parent.const_defined?(parts.last, false)
      parent.const_set(parts.last, value)
      @stubbed_constants << name
    end
  end
end
