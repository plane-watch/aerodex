# frozen_string_literal: true

module Admin
  # Controller for triggering processor jobs.
  class ProcessorsController < BaseController
    # Known processor entity types.
    PROCESSOR_ENTITY_TYPES = %w[
      Aircraft
      AircraftType
      Airport
      Country
      Manufacturer
      Operator
      Route
      Runway
    ].freeze

    def index
      @processors = PROCESSOR_ENTITY_TYPES.map do |entity_type|
        processor_class = "Processors::#{entity_type}::#{entity_type}"
        last_batch = StagedBatch.where(entity_type: entity_type).recent.first
        processing_batch = StagedBatch.processing.find_by(entity_type: entity_type)

        {
          entity_type: entity_type,
          processor_class: processor_class,
          last_batch: last_batch,
          processing: processing_batch.present?,
          processing_batch: processing_batch
        }
      end
    end

    def create
      entity_type = params[:entity_type]

      unless PROCESSOR_ENTITY_TYPES.include?(entity_type)
        redirect_to admin_processors_path, alert: "Unknown processor: #{entity_type}"
        return
      end

      processor_class = "Processors::#{entity_type}::#{entity_type}"

      # Verify the processor class exists
      begin
        processor_class.constantize
      rescue NameError
        redirect_to admin_processors_path, alert: "Processor not found: #{processor_class}"
        return
      end

      ProcessorJob.perform_later(processor_class, triggered_by_id: current_user.id)
      redirect_to admin_processors_path, notice: "#{entity_type} processor job enqueued."
    end
  end
end
