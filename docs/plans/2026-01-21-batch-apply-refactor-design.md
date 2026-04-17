# Batch Apply Refactor Design

## Overview

Refactor the `StagedBatch#apply!` operation to:
1. Use standard ActiveRecord (`save!`/`update!`) instead of bulk operations
2. Run in a background job for large batches
3. Show real-time progress via Turbo Streams over ActionCable

## Decisions

| Decision | Choice |
|----------|--------|
| Batch sizes | Variable (hundreds to thousands) |
| Real-time updates | Turbo Streams via ActionCable |
| Progress granularity | Percentage-based (~1% intervals) |
| Navigation during apply | Job continues; status shown on return |
| Partial failure handling | Full transaction rollback |
| UI during apply | Progress bar replaces action buttons |
| New status | Add `applying` status |

## Architecture

### Flow

```
User clicks "Apply"
    ↓
Controller sets status to `applying`, enqueues ApplyBatchJob
    ↓
Browser subscribes to StagedBatchChannel for this batch
    ↓
Job applies changes one-by-one inside a transaction
    ↓
Job broadcasts progress via Turbo Stream (every ~1%)
    ↓
On success: status → `applied`, broadcast final state
On failure: transaction rolls back, status → `failed`, broadcast error
    ↓
UI updates automatically via Turbo Stream
```

### Components

| Component | Type | Purpose |
|-----------|------|---------|
| `ApplyBatchJob` | New job | Runs apply in background |
| `StagedBatchChannel` | New channel | Broadcasts progress updates |
| `StagedBatch` | Model changes | New status, refactored `apply!` |
| `StagedBatchesController#apply` | Controller change | Enqueue job instead of direct call |
| `batch_apply_controller.js` | New Stimulus | Progress bar UI |

## Model Changes (`StagedBatch`)

### New Status

Add `applying: 8` to the status enum:
- `pending` → `applying` (when job starts)
- `applying` → `applied` (on success)
- `applying` → `failed` (on error, after rollback)

### New Columns

```ruby
add_column :staged_batches, :apply_progress, :integer, default: 0
add_column :staged_batches, :apply_total, :integer
```

### Refactored `apply!`

```ruby
def apply!(by:)
  raise InvalidStatusError unless applying?

  transaction do
    check_for_stale_data!

    staged_changes.find_each.with_index do |change, index|
      apply_single_change(change)
      broadcast_progress_if_needed(index)
    end

    self.status = :applied
    self.applied_at = Time.current
    self.reviewed_by = by
    self.reviewed_at = Time.current
    self.apply_progress = 100
    save!
  end

  broadcast_completion
  run_post_apply_hooks
rescue StandardError => e
  update!(
    status: :failed,
    error_message: "#{e.class}: #{e.message}",
    apply_progress: 0
  )
  broadcast_completion
  raise
end

private

def apply_single_change(change)
  model_class = change.record_type.constantize

  if change.create?
    record = model_class.new(change.new_values)
    record.save!
  else
    record = model_class.find(change.record_id)
    record.update!(change.new_values)
  end
end
```

### Broadcasting

```ruby
PROGRESS_BROADCAST_INTERVAL = 1 # Broadcast every 1%

def broadcast_progress_if_needed(index)
  total = staged_changes.count
  new_progress = ((index + 1) * 100 / total).to_i

  return if new_progress == apply_progress
  return if new_progress % PROGRESS_BROADCAST_INTERVAL != 0 && new_progress != 100

  update_column(:apply_progress, new_progress)
  broadcast_progress(new_progress)
end

def broadcast_progress(progress)
  StagedBatchChannel.broadcast_to(self, {
    event: "progress",
    progress: progress,
    status: status
  })
end

def broadcast_completion
  StagedBatchChannel.broadcast_to(self, {
    event: "complete",
    status: status,
    error_message: error_message
  })
end
```

## Background Job (`ApplyBatchJob`)

```ruby
class ApplyBatchJob < ApplicationJob
  queue_as :default

  def perform(batch_id, user_id:)
    @batch = StagedBatch.find(batch_id)
    @user = user_id ? User.find(user_id) : nil

    @batch.apply!(by: @user)
  rescue StandardError => e
    raise
  end
end
```

## Controller Changes

```ruby
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
```

## ActionCable Channel

```ruby
# app/channels/staged_batch_channel.rb
class StagedBatchChannel < ApplicationCable::Channel
  def subscribed
    batch = StagedBatch.find(params[:id])
    stream_for batch
  end
end
```

## Stimulus Controller

```javascript
// app/javascript/controllers/batch_apply_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@actioncable/core"

export default class extends Controller {
  static targets = ["actions", "progress", "progressBar", "progressText"]
  static values = { batchId: String, status: String }

  connect() {
    if (this.statusValue === "applying") {
      this.showProgress()
      this.subscribe()
    }
  }

  disconnect() {
    this.unsubscribe()
  }

  subscribe() {
    this.channel = createConsumer().subscriptions.create(
      { channel: "StagedBatchChannel", id: this.batchIdValue },
      { received: (data) => this.handleMessage(data) }
    )
  }

  unsubscribe() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }

  showProgress() {
    this.actionsTarget.classList.add("hidden")
    this.progressTarget.classList.remove("hidden")
  }

  handleMessage(data) {
    if (data.event === "progress") {
      this.updateProgress(data.progress)
    } else if (data.event === "complete") {
      this.handleComplete(data)
    }
  }

  updateProgress(progress) {
    this.progressBarTarget.style.width = `${progress}%`
    this.progressTextTarget.textContent = `Applying... ${progress}%`
  }

  handleComplete(data) {
    window.location.reload()
  }
}
```

## View Changes

Replace action buttons area in `show.html.erb` with Stimulus-controlled container:

```erb
<div data-controller="batch-apply"
     data-batch-apply-batch-id-value="<%= @batch.id %>"
     data-batch-apply-status-value="<%= @batch.status %>">

  <%# Action buttons (shown when pending) %>
  <div data-batch-apply-target="actions" class="<%= 'hidden' if @batch.applying? %>">
    <% if @batch.pending? %>
      <%= button_to "Apply", apply_admin_staged_batch_path(@batch), ... %>
      <%= button_to "Reject", reject_admin_staged_batch_path(@batch), ... %>
    <% end %>
  </div>

  <%# Progress bar (shown when applying) %>
  <div data-batch-apply-target="progress" class="<%= 'hidden' unless @batch.applying? %>">
    <div class="text-sm font-medium text-gray-700 mb-2" data-batch-apply-target="progressText">
      Applying... <%= @batch.apply_progress %>%
    </div>
    <div class="w-full bg-gray-200 rounded-full h-2.5">
      <div data-batch-apply-target="progressBar"
           class="bg-indigo-600 h-2.5 rounded-full transition-all duration-300"
           style="width: <%= @batch.apply_progress %>%"></div>
    </div>
  </div>
</div>
```

## Post-Apply Hooks

Counter caches and reindexing happen in `run_post_apply_hooks` after successful apply:

```ruby
def run_post_apply_hooks
  reset_counter_caches
  reindex_for_search
end
```

Since we now use `save!`/`update!`, counter caches are updated automatically via ActiveRecord callbacks. The explicit reset is a safety net for any edge cases.

## Migration

```ruby
class AddApplyProgressToStagedBatches < ActiveRecord::Migration[7.1]
  def change
    add_column :staged_batches, :apply_progress, :integer, default: 0
    add_column :staged_batches, :apply_total, :integer
  end
end
```

## Testing Considerations

- Test `apply!` with various batch sizes
- Test transaction rollback on validation failure
- Test progress broadcasting (mock ActionCable)
- Test job error handling
- Test UI states (pending, applying, applied, failed)
