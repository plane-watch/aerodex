# frozen_string_literal: true

# Base job for running data processors.
#
# Processors are run in the background and create StagedBatch records
# that must be reviewed and approved before changes are applied.
#
# @example Enqueue a processor
#   ProcessorJob.perform_later("Processors::Aircraft::Aircraft")
#
# @example Run synchronously
#   ProcessorJob.perform_now("Processors::Aircraft::Aircraft")
#
class ProcessorJob < ApplicationJob
  queue_as :processors

  # Called before perform to set up tracking.
  before_perform do |job|
    @job_id = job.job_id
  end

  # Runs the specified processor.
  #
  # @param processor_class_name [String] The fully-qualified processor class name
  # @param triggered_by_id [Integer, nil] The ID of the user who triggered the run
  def perform(processor_class_name, triggered_by_id: nil)
    processor_class = processor_class_name.constantize
    triggered_by = triggered_by_id ? User.find(triggered_by_id) : nil

    batch = processor_class.combine_sources(triggered_by: triggered_by)

    # Update the batch with job tracking info
    batch.update!(job_id: @job_id) if batch.is_a?(StagedBatch)
  rescue StandardError => e
    # If we have a batch, mark it as failed
    if defined?(batch) && batch.is_a?(StagedBatch)
      batch.update!(
        status: :failed,
        error_message: "#{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      )
    end
    raise
  end
end
