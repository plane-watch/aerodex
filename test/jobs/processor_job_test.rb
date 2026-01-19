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

  private

  def stub_const(name, value)
    parts = name.split("::")
    parent = parts[0..-2].inject(Object) { |mod, part| mod.const_get(part) rescue mod.const_set(part, Module.new) }
    parent.const_set(parts.last, value) unless parent.const_defined?(parts.last)
  end
end
