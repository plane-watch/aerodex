# frozen_string_literal: true

# Adds a per-change completion marker so a staged batch can be applied in
# chunked, committed transactions and resumed after a failure. The composite
# index makes "the unapplied changes for this batch" an indexed lookup.
class AddAppliedAtToStagedChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :staged_changes, :applied_at, :datetime
    add_index :staged_changes, %i[staged_batch_id applied_at]
  end
end
