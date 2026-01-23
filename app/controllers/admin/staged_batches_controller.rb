# frozen_string_literal: true

module Admin
  # Controller for managing staged batches.
  # Provides index, show, apply, reject, rollback, and status actions.
  class StagedBatchesController < BaseController
    before_action :set_staged_batch, only: [:show, :apply, :reject, :rollback, :status]

    def index
      @batches = StagedBatch.recent
      @batches = @batches.where(status: params[:status]) if params[:status].present?
      @batches = @batches.for_entity(params[:entity_type]) if params[:entity_type].present?

      @pagy, @batches = pagy(@batches, items: 25)

      # For filter dropdowns
      @entity_types = StagedBatch.distinct.pluck(:entity_type).sort
      @statuses = StagedBatch.statuses.keys
    end

    def show
      @changes = @batch.staged_changes
      @changes = @changes.where(operation: params[:operation]) if params[:operation].present?
      @changes = @changes.where("record_identifier ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      @pagy, @changes = pagy(@changes, items: 50)

      # Counts for the grouping headers
      @creates_count = @batch.staged_changes.creates.count
      @updates_count = @batch.staged_changes.updates.count
    end

    def apply
      unless @batch.pending?
        redirect_to admin_staged_batch_path(@batch), alert: "Batch is not pending"
        return
      end

      @batch.update!(
        status: :applying,
        apply_progress: 0,
        apply_total: @batch.staged_changes.count
      )
      ApplyBatchJob.perform_later(@batch.id, user_id: current_user.id)

      redirect_to admin_staged_batch_path(@batch), notice: "Applying batch in background..."
    end

    def reject
      @batch.reject!(by: current_user, reason: params[:reason])
      redirect_to admin_staged_batch_path(@batch), notice: "Batch rejected."
    rescue StagedBatch::InvalidStatusError => e
      redirect_to admin_staged_batch_path(@batch), alert: "Failed to reject batch: #{e.message}"
    end

    def rollback
      # TODO: Implement rollback in Phase 7
      redirect_to admin_staged_batch_path(@batch), alert: "Rollback not yet implemented."
    end

    # GET /admin/staged_batches/:id/status
    # Returns JSON status for fallback polling when ActionCable events are missed.
    def status
      render json: {
        status: @batch.status,
        processing_progress: @batch.processing_progress,
        apply_progress: @batch.apply_progress
      }
    end

    private

    def set_staged_batch
      @batch = StagedBatch.find(params[:id])
    end
  end
end
