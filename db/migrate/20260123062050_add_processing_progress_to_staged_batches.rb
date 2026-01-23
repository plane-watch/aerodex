class AddProcessingProgressToStagedBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :staged_batches, :processing_progress, :integer, default: 0
    add_column :staged_batches, :processing_total, :integer
  end
end
