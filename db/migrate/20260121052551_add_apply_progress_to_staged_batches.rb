class AddApplyProgressToStagedBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :staged_batches, :apply_progress, :integer, default: 0
    add_column :staged_batches, :apply_total, :integer
  end
end
