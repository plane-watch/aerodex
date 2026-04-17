# Batch Apply Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor StagedBatch#apply! to use standard ActiveRecord, run in a background job, and show real-time progress via ActionCable.

**Architecture:** Controller sets status to `applying` and enqueues ApplyBatchJob. Job applies changes one-by-one inside a transaction, broadcasting progress via ActionCable. Stimulus controller updates progress bar in real-time.

**Tech Stack:** Rails 7, ActiveJob, ActionCable, Turbo, Stimulus, Tailwind CSS

**Design Document:** `docs/plans/2026-01-21-batch-apply-refactor-design.md`

---

## Task 0: Database Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_apply_progress_to_staged_batches.rb`

**Step 1: Generate the migration**

Run:
```bash
./bin/rails generate migration AddApplyProgressToStagedBatches apply_progress:integer apply_total:integer
```

**Step 2: Edit migration to set default**

Edit the generated file to add `default: 0` for apply_progress:

```ruby
class AddApplyProgressToStagedBatches < ActiveRecord::Migration[7.1]
  def change
    add_column :staged_batches, :apply_progress, :integer, default: 0
    add_column :staged_batches, :apply_total, :integer
  end
end
```

**Step 3: Run migration**

Run: `./bin/rails db:migrate`

**Step 4: Verify schema updated**

Run: `grep -A2 "apply_progress" db/schema.rb`
Expected: Shows both columns in staged_batches table

**Step 5: Commit**

```bash
git add db/migrate/*_add_apply_progress_to_staged_batches.rb db/schema.rb
git commit -m "db: add apply_progress columns to staged_batches"
```

---

## Task 1: Add `applying` Status to StagedBatch

**Files:**
- Modify: `app/models/staged_batch.rb`
- Modify: `test/models/staged_batch_test.rb`

**Step 1: Write the failing test**

Add to `test/models/staged_batch_test.rb`:

```ruby
test "applying status exists" do
  batch = StagedBatch.new(
    processor_type: "Test",
    entity_type: "Test",
    status: :applying
  )
  assert batch.applying?
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /applying_status_exists/`
Expected: FAIL with ArgumentError (invalid status)

**Step 3: Add applying status to enum**

In `app/models/staged_batch.rb`, update the enum:

```ruby
enum :status, {
  processing: 0,
  pending: 1,
  approved: 2,
  applied: 3,
  rejected: 4,
  superseded: 5,
  rolled_back: 6,
  failed: 7,
  applying: 8
}
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /applying_status_exists/`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb
git commit -m "feat: add applying status to StagedBatch"
```

---

## Task 2: Refactor apply! to Use Standard ActiveRecord

**Files:**
- Modify: `app/models/staged_batch.rb`
- Modify: `test/models/staged_batch_test.rb`

**Step 1: Write test for apply! accepting applying status**

Add to `test/models/staged_batch_test.rb`:

```ruby
test "apply! works when status is applying" do
  batch = StagedBatch.create!(
    processor_type: "Processors::Country::Country",
    entity_type: "Country",
    status: :applying,
    apply_progress: 0,
    apply_total: 1
  )
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "WW",
    operation: :create,
    diff: {
      "name" => [nil, "Test Country W"],
      "iso_2char_code" => [nil, "WW"],
      "iso_3char_code" => [nil, "WWW"]
    }
  )

  batch.apply!(by: nil)

  assert_equal "applied", batch.status
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /apply.*works_when_status_is_applying/`
Expected: FAIL with InvalidStatusError

**Step 3: Update apply! to accept applying status**

In `app/models/staged_batch.rb`, change the status check in `apply!`:

```ruby
def apply!(by:)
  raise InvalidStatusError, "Batch must be pending or applying (current: #{status})" unless pending? || applying?
  raise ApplyError, "Cannot apply batch with no changes" if staged_changes.empty?
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /apply.*works_when_status_is_applying/`
Expected: PASS

**Step 5: Write test for transaction rollback on failure**

Add to `test/models/staged_batch_test.rb`:

```ruby
test "apply! rolls back all changes on validation failure" do
  batch = StagedBatch.create!(
    processor_type: "Processors::Country::Country",
    entity_type: "Country",
    status: :applying
  )

  # First change will succeed
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "QQ",
    operation: :create,
    diff: {
      "name" => [nil, "Country Q"],
      "iso_2char_code" => [nil, "QQ"],
      "iso_3char_code" => [nil, "QQQ"]
    }
  )

  # Second change will fail (missing required field)
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "RR",
    operation: :create,
    diff: {
      "name" => [nil, "Country R"]
      # Missing iso_2char_code - will fail validation
    }
  )

  assert_raises(ActiveRecord::RecordInvalid) do
    batch.apply!(by: nil)
  end

  # First country should NOT exist (rolled back)
  assert_nil Country.find_by(iso_2char_code: "QQ")

  # Batch should be marked as failed
  batch.reload
  assert_equal "failed", batch.status
  assert_includes batch.error_message, "Validation failed"
end
```

**Step 6: Run test to verify it fails**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /rolls_back_all_changes_on_validation_failure/`
Expected: FAIL (batch status not updated to failed)

**Step 7: Refactor apply! with proper error handling**

Replace the entire `apply!` method and private helpers in `app/models/staged_batch.rb`:

```ruby
# Applies all staged changes to the database.
#
# @param by [User, nil] The user approving the batch
# @raise [InvalidStatusError] If batch is not pending or applying
# @raise [ApplyError] If apply fails
def apply!(by:)
  raise InvalidStatusError, "Batch must be pending or applying (current: #{status})" unless pending? || applying?
  raise ApplyError, "Cannot apply batch with no changes" if staged_changes.empty?

  transaction do
    check_for_stale_data!
    apply_changes!

    self.status = :applied
    self.applied_at = Time.current
    self.reviewed_by = by
    self.reviewed_at = Time.current
    self.apply_progress = 100
    save!
  end

  run_post_apply_hooks
rescue StandardError => e
  # Record the failure (outside transaction so it persists)
  update!(
    status: :failed,
    error_message: "#{e.class}: #{e.message}",
    apply_progress: 0
  )
  raise
end
```

Replace `apply_changes!`, `apply_creates`, and `apply_updates` with:

```ruby
# Applies all staged changes using standard ActiveRecord.
def apply_changes!
  staged_changes.find_each.with_index do |change, index|
    apply_single_change(change)
    update_apply_progress(index)
  end
end

# Applies a single staged change using save!/update!
#
# @param change [StagedChange] The change to apply
def apply_single_change(change)
  model_class = change.record_type.constantize

  if change.operation == "create"
    record = model_class.new(change.new_values)
    record.save!
  else
    record = model_class.find(change.record_id)
    record.update!(change.new_values)
  end
end

# Updates apply progress percentage.
#
# @param index [Integer] Current change index (0-based)
def update_apply_progress(index)
  total = apply_total || staged_changes.count
  new_progress = ((index + 1) * 100 / total).to_i
  return if new_progress == apply_progress

  update_column(:apply_progress, new_progress)
end
```

**Step 8: Run test to verify it passes**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /rolls_back_all_changes_on_validation_failure/`
Expected: PASS

**Step 9: Run all staged batch tests**

Run: `./bin/rails test test/models/staged_batch_test.rb`
Expected: All tests PASS

**Step 10: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb
git commit -m "refactor: apply! uses standard ActiveRecord with proper rollback"
```

---

## Task 3: Create ApplyBatchJob

**Files:**
- Create: `app/jobs/apply_batch_job.rb`
- Create: `test/jobs/apply_batch_job_test.rb`

**Step 1: Write the failing test**

Create `test/jobs/apply_batch_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ApplyBatchJobTest < ActiveJob::TestCase
  test "perform applies the batch" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :applying,
      apply_progress: 0,
      apply_total: 1
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "JJ",
      operation: :create,
      diff: {
        "name" => [nil, "Job Test Country"],
        "iso_2char_code" => [nil, "JJ"],
        "iso_3char_code" => [nil, "JJJ"]
      }
    )

    ApplyBatchJob.perform_now(batch.id, user_id: nil)

    batch.reload
    assert_equal "applied", batch.status
    assert_not_nil Country.find_by(iso_2char_code: "JJ")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/jobs/apply_batch_job_test.rb`
Expected: FAIL with NameError (ApplyBatchJob not defined)

**Step 3: Create the job**

Create `app/jobs/apply_batch_job.rb`:

```ruby
# frozen_string_literal: true

# Background job for applying staged batches.
#
# Applies all staged changes in a transaction. On success, updates
# the batch status to applied. On failure, rolls back changes and
# marks the batch as failed.
#
# @example Enqueue a batch to be applied
#   ApplyBatchJob.perform_later(batch.id, user_id: current_user.id)
#
class ApplyBatchJob < ApplicationJob
  queue_as :default

  # Applies the staged batch.
  #
  # @param batch_id [String] The UUID of the batch to apply
  # @param user_id [Integer, nil] The ID of the user who approved the batch
  def perform(batch_id, user_id:)
    batch = StagedBatch.find(batch_id)
    user = user_id ? User.find(user_id) : nil

    batch.apply!(by: user)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/jobs/apply_batch_job_test.rb`
Expected: PASS

**Step 5: Write test for error handling**

Add to `test/jobs/apply_batch_job_test.rb`:

```ruby
test "perform marks batch as failed on error" do
  batch = StagedBatch.create!(
    processor_type: "Processors::Country::Country",
    entity_type: "Country",
    status: :applying
  )
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "KK",
    operation: :create,
    diff: {
      "name" => [nil, "Incomplete Country"]
      # Missing required iso_2char_code
    }
  )

  assert_raises(ActiveRecord::RecordInvalid) do
    ApplyBatchJob.perform_now(batch.id, user_id: nil)
  end

  batch.reload
  assert_equal "failed", batch.status
  assert_includes batch.error_message, "Validation failed"
end
```

**Step 6: Run test to verify it passes**

Run: `./bin/rails test test/jobs/apply_batch_job_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add app/jobs/apply_batch_job.rb test/jobs/apply_batch_job_test.rb
git commit -m "feat: add ApplyBatchJob for background batch application"
```

---

## Task 4: Create StagedBatchChannel

**Files:**
- Create: `app/channels/staged_batch_channel.rb`
- Create: `test/channels/staged_batch_channel_test.rb`

**Step 1: Write the failing test**

Create `test/channels/staged_batch_channel_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StagedBatchChannelTest < ActionCable::Channel::TestCase
  test "subscribes to a batch" do
    batch = StagedBatch.create!(
      processor_type: "Test",
      entity_type: "Test"
    )

    subscribe id: batch.id

    assert subscription.confirmed?
  end

  test "rejects subscription for non-existent batch" do
    subscribe id: "non-existent-uuid"

    assert subscription.rejected?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/channels/staged_batch_channel_test.rb`
Expected: FAIL with NameError (StagedBatchChannel not defined)

**Step 3: Create the channel**

Create `app/channels/staged_batch_channel.rb`:

```ruby
# frozen_string_literal: true

# ActionCable channel for real-time batch apply progress updates.
#
# Clients subscribe to a specific batch and receive progress updates
# as the batch is applied.
#
# @example Subscribe from JavaScript
#   consumer.subscriptions.create(
#     { channel: "StagedBatchChannel", id: batchId },
#     { received: (data) => handleMessage(data) }
#   )
#
class StagedBatchChannel < ApplicationCable::Channel
  # Subscribes to progress updates for a specific batch.
  def subscribed
    batch = StagedBatch.find_by(id: params[:id])

    if batch
      stream_for batch
    else
      reject
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/channels/staged_batch_channel_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/channels/staged_batch_channel.rb test/channels/staged_batch_channel_test.rb
git commit -m "feat: add StagedBatchChannel for apply progress updates"
```

---

## Task 5: Add Broadcasting to StagedBatch

**Files:**
- Modify: `app/models/staged_batch.rb`
- Modify: `test/models/staged_batch_test.rb`

**Step 1: Write test for progress broadcasting**

Add to `test/models/staged_batch_test.rb`:

```ruby
test "apply! broadcasts progress updates" do
  batch = StagedBatch.create!(
    processor_type: "Processors::Country::Country",
    entity_type: "Country",
    status: :applying,
    apply_progress: 0,
    apply_total: 2
  )

  # Add two changes so we can track progress
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "P1",
    operation: :create,
    diff: {
      "name" => [nil, "Country P1"],
      "iso_2char_code" => [nil, "P1"],
      "iso_3char_code" => [nil, "PP1"]
    }
  )
  batch.staged_changes.create!(
    record_type: "Country",
    record_identifier: "P2",
    operation: :create,
    diff: {
      "name" => [nil, "Country P2"],
      "iso_2char_code" => [nil, "P2"],
      "iso_3char_code" => [nil, "PP2"]
    }
  )

  broadcasts = []
  # Stub the broadcast to capture messages
  StagedBatchChannel.stub :broadcast_to, ->(target, message) { broadcasts << message } do
    batch.apply!(by: nil)
  end

  # Should have progress broadcasts and a completion broadcast
  assert broadcasts.any? { |b| b[:event] == "progress" }
  assert broadcasts.any? { |b| b[:event] == "complete" && b[:status] == "applied" }
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /broadcasts_progress_updates/`
Expected: FAIL (no broadcasts)

**Step 3: Add broadcasting methods to StagedBatch**

Add to `app/models/staged_batch.rb` in the private section:

```ruby
# Minimum percentage change before broadcasting (prevents flooding)
PROGRESS_BROADCAST_INTERVAL = 1

# Broadcasts progress if the percentage has changed.
#
# @param index [Integer] Current change index (0-based)
def broadcast_progress_if_needed(index)
  total = apply_total || staged_changes.count
  new_progress = ((index + 1) * 100 / total).to_i

  return if new_progress == apply_progress
  # Only broadcast at intervals, but always broadcast 100%
  return if (new_progress % PROGRESS_BROADCAST_INTERVAL != 0) && new_progress != 100

  update_column(:apply_progress, new_progress)
  broadcast_progress(new_progress)
end

# Broadcasts current progress to subscribed clients.
#
# @param progress [Integer] Progress percentage (0-100)
def broadcast_progress(progress)
  StagedBatchChannel.broadcast_to(self, {
    event: "progress",
    progress: progress,
    status: status
  })
end

# Broadcasts completion (success or failure) to subscribed clients.
def broadcast_completion
  StagedBatchChannel.broadcast_to(self, {
    event: "complete",
    status: status,
    error_message: error_message
  })
end
```

**Step 4: Update apply_changes! to use broadcasting**

Replace `update_apply_progress` call with `broadcast_progress_if_needed` in `apply_changes!`:

```ruby
def apply_changes!
  staged_changes.find_each.with_index do |change, index|
    apply_single_change(change)
    broadcast_progress_if_needed(index)
  end
end
```

**Step 5: Add broadcast_completion calls to apply!**

Update `apply!` to broadcast completion:

```ruby
def apply!(by:)
  raise InvalidStatusError, "Batch must be pending or applying (current: #{status})" unless pending? || applying?
  raise ApplyError, "Cannot apply batch with no changes" if staged_changes.empty?

  transaction do
    check_for_stale_data!
    apply_changes!

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
```

**Step 6: Remove the old update_apply_progress method**

Delete the `update_apply_progress` method (now replaced by `broadcast_progress_if_needed`).

**Step 7: Run test to verify it passes**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /broadcasts_progress_updates/`
Expected: PASS

**Step 8: Run all staged batch tests**

Run: `./bin/rails test test/models/staged_batch_test.rb`
Expected: All tests PASS

**Step 9: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb
git commit -m "feat: broadcast apply progress via ActionCable"
```

---

## Task 6: Update Controller to Enqueue Job

**Files:**
- Modify: `app/controllers/admin/staged_batches_controller.rb`
- Modify: `test/controllers/admin/staged_batches_controller_test.rb` (if exists, otherwise create)

**Step 1: Check if controller test exists**

Run: `ls test/controllers/admin/`

If no test exists, create `test/controllers/admin/staged_batches_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::StagedBatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "apply enqueues job and redirects" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "CT",
      operation: :create,
      diff: {
        "name" => [nil, "Controller Test"],
        "iso_2char_code" => [nil, "CT"],
        "iso_3char_code" => [nil, "CTT"]
      }
    )

    assert_enqueued_with(job: ApplyBatchJob) do
      post apply_admin_staged_batch_path(batch)
    end

    batch.reload
    assert_equal "applying", batch.status
    assert_redirected_to admin_staged_batch_path(batch)
  end

  test "apply rejects non-pending batch" do
    batch = StagedBatch.create!(
      processor_type: "Test",
      entity_type: "Test",
      status: :applied
    )

    post apply_admin_staged_batch_path(batch)

    assert_redirected_to admin_staged_batch_path(batch)
    assert_equal "Batch is not pending", flash[:alert]
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/controllers/admin/staged_batches_controller_test.rb -n /apply_enqueues_job/`
Expected: FAIL (batch status is "applied" not "applying", no job enqueued)

**Step 3: Update controller apply action**

Replace the `apply` method in `app/controllers/admin/staged_batches_controller.rb`:

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

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/controllers/admin/staged_batches_controller_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/controllers/admin/staged_batches_controller.rb test/controllers/admin/staged_batches_controller_test.rb
git commit -m "feat: apply action enqueues ApplyBatchJob"
```

---

## Task 7: Create Stimulus Controller for Progress UI

**Files:**
- Create: `app/javascript/controllers/batch_apply_controller.js`

**Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/batch_apply_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Handles real-time progress updates for batch apply operations.
//
// Connects to StagedBatchChannel via ActionCable and updates
// the progress bar as the batch is applied.
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
    this.consumer = createConsumer()
    this.channel = this.consumer.subscriptions.create(
      { channel: "StagedBatchChannel", id: this.batchIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
  }

  unsubscribe() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  showProgress() {
    if (this.hasActionsTarget) {
      this.actionsTarget.classList.add("hidden")
    }
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove("hidden")
    }
  }

  handleMessage(data) {
    if (data.event === "progress") {
      this.updateProgress(data.progress)
    } else if (data.event === "complete") {
      this.handleComplete(data)
    }
  }

  updateProgress(progress) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${progress}%`
    }
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `Applying... ${progress}%`
    }
  }

  handleComplete(data) {
    // Reload page to show final state (applied or failed)
    window.location.reload()
  }
}
```

**Step 2: Verify controller is auto-loaded**

Run: `grep -r "batch-apply" app/javascript/`
Expected: Should find the controller (Stimulus auto-loads from controllers directory)

**Step 3: Commit**

```bash
git add app/javascript/controllers/batch_apply_controller.js
git commit -m "feat: add Stimulus controller for batch apply progress"
```

---

## Task 8: Update View with Progress UI

**Files:**
- Modify: `app/views/admin/staged_batches/show.html.erb`

**Step 1: Read current view structure**

Review the current action buttons section in `show.html.erb` (lines 54-76).

**Step 2: Replace action buttons section with Stimulus-controlled container**

Replace the action buttons section (the `<div class="mt-5 sm:ml-6...">` block) with:

```erb
<%# Action buttons and progress indicator %>
<div class="mt-5 sm:ml-6 sm:mt-0 sm:flex sm:flex-shrink-0 sm:items-center"
     data-controller="batch-apply"
     data-batch-apply-batch-id-value="<%= @batch.id %>"
     data-batch-apply-status-value="<%= @batch.status %>">

  <%# Action buttons (shown when pending) %>
  <div data-batch-apply-target="actions"
       class="flex gap-2 <%= 'hidden' if @batch.applying? %>">
    <% if @batch.pending? %>
      <%= button_to "Apply",
                    apply_admin_staged_batch_path(@batch),
                    method: :post,
                    class: "inline-flex items-center rounded-md bg-green-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-green-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600",
                    data: { turbo_confirm: "Are you sure you want to apply #{@batch.staged_changes.count} changes?" } %>

      <%= button_to "Reject",
                    reject_admin_staged_batch_path(@batch),
                    method: :post,
                    class: "inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600",
                    data: { turbo_confirm: "Are you sure you want to reject this batch?" } %>
    <% elsif @batch.applied? %>
      <%= button_to "Rollback",
                    rollback_admin_staged_batch_path(@batch),
                    method: :post,
                    class: "inline-flex items-center rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-orange-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600",
                    data: { turbo_confirm: "Are you sure you want to rollback this batch? This cannot be undone." } %>
    <% end %>
  </div>

  <%# Progress indicator (shown when applying) %>
  <div data-batch-apply-target="progress"
       class="w-64 <%= 'hidden' unless @batch.applying? %>">
    <div class="text-sm font-medium text-gray-700 mb-2"
         data-batch-apply-target="progressText">
      Applying... <%= @batch.apply_progress %>%
    </div>
    <div class="w-full bg-gray-200 rounded-full h-2.5">
      <div data-batch-apply-target="progressBar"
           class="bg-indigo-600 h-2.5 rounded-full transition-all duration-300 ease-out"
           style="width: <%= @batch.apply_progress %>%"></div>
    </div>
    <div class="text-xs text-gray-500 mt-1">
      Processing <%= @batch.apply_total || @batch.staged_changes.count %> changes
    </div>
  </div>
</div>
```

**Step 3: Start the Rails server and test manually**

Run: `./bin/rails server`

1. Navigate to a pending batch
2. Click "Apply"
3. Verify progress bar appears and updates
4. Verify page reloads on completion

**Step 4: Commit**

```bash
git add app/views/admin/staged_batches/show.html.erb
git commit -m "feat: add progress bar UI for batch apply"
```

---

## Task 9: Clean Up Old Bulk Operation Code

**Files:**
- Modify: `app/models/staged_batch.rb`

**Step 1: Remove old apply_creates and apply_updates methods**

These methods are no longer used. Delete them from `app/models/staged_batch.rb`:

- Delete `apply_creates` method
- Delete `apply_updates` method

**Step 2: Run all tests to ensure nothing breaks**

Run: `./bin/rails test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/models/staged_batch.rb
git commit -m "chore: remove unused bulk operation methods"
```

---

## Task 10: Remove Counter Cache SQL from StagedBatch

**Files:**
- Modify: `app/models/staged_batch.rb`

Since we now use standard ActiveRecord (`save!`/`update!`), counter caches are updated automatically via callbacks. The raw SQL counter cache reset in `run_post_apply_hooks` is no longer necessary.

**Step 1: Simplify run_post_apply_hooks**

Replace the counter cache methods with a simpler version:

```ruby
# Runs post-apply hooks like reindexing.
def run_post_apply_hooks
  reindex_for_search
end

# Reindexes the affected model for search.
def reindex_for_search
  model_class = entity_type.safe_constantize
  return unless model_class&.respond_to?(:reindex!)

  model_class.reindex!
rescue StandardError => e
  Rails.logger.error "Failed to reindex #{entity_type}: #{e.message}"
end
```

**Step 2: Remove counter cache methods**

Delete these methods:
- `reset_counter_caches`
- `counter_cache_updates_for_entity_type`

**Step 3: Run all tests**

Run: `./bin/rails test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/models/staged_batch.rb
git commit -m "chore: remove manual counter cache reset (now handled by callbacks)"
```

---

## Task 11: Update Helper for Applying Status Badge

**Files:**
- Modify: `app/helpers/admin/staged_batches_helper.rb`

**Step 1: Add applying status styling**

In `status_badge_classes`, add a case for `applying`:

```ruby
when "applying"
  "bg-blue-50 text-blue-700 ring-blue-600/20"
```

(Add this after the `"processing"` case.)

**Step 2: Verify badge displays correctly**

Start server and check that applying batches show blue badge.

**Step 3: Commit**

```bash
git add app/helpers/admin/staged_batches_helper.rb
git commit -m "feat: add badge styling for applying status"
```

---

## Task 12: Final Integration Test

**Step 1: Run full test suite**

Run: `./bin/rails test`
Expected: All tests PASS

**Step 2: Manual end-to-end test**

1. Run a processor to create a pending batch
2. Navigate to batch show page
3. Click Apply
4. Watch progress bar fill up
5. Verify page reloads to show "Applied" status
6. Verify records were created/updated
7. Verify counter caches are correct

**Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address integration test findings"
```

---

## Summary

| Task | Description |
|------|-------------|
| 0 | Add apply_progress columns to staged_batches |
| 1 | Add `applying` status to enum |
| 2 | Refactor apply! to use standard ActiveRecord |
| 3 | Create ApplyBatchJob |
| 4 | Create StagedBatchChannel |
| 5 | Add broadcasting to StagedBatch |
| 6 | Update controller to enqueue job |
| 7 | Create Stimulus controller |
| 8 | Update view with progress UI |
| 9 | Clean up old bulk operation code |
| 10 | Remove manual counter cache reset |
| 11 | Update helper for applying status badge |
| 12 | Final integration test |
