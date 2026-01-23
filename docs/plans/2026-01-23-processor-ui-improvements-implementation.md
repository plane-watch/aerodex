# Processor UI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add processing progress tracking, fix apply completion bug, and replace prototype pending approvals widget with real data.

**Architecture:** Hook into existing Ruby ProgressBar infrastructure to broadcast processing progress via ActionCable. Extend the existing `batch_apply_controller.js` to handle both processing and apply events, with fallback polling for reliability. Replace hardcoded dashboard widget with real StagedBatch queries.

**Tech Stack:** Rails 7, ActionCable, Stimulus.js, Tailwind CSS

---

## Task 1: Database Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_processing_progress_to_staged_batches.rb`

**Step 1: Generate migration**

Run:
```bash
./bin/rails generate migration AddProcessingProgressToStagedBatches processing_progress:integer processing_total:integer
```

**Step 2: Update migration with defaults**

Edit the generated migration to add default value:

```ruby
class AddProcessingProgressToStagedBatches < ActiveRecord::Migration[7.1]
  def change
    add_column :staged_batches, :processing_progress, :integer, default: 0
    add_column :staged_batches, :processing_total, :integer
  end
end
```

**Step 3: Run migration**

Run: `./bin/rails db:migrate`

**Step 4: Commit**

```bash
git add db/migrate/*_add_processing_progress_to_staged_batches.rb db/schema.rb
git commit -m "feat: add processing_progress columns to staged_batches"
```

---

## Task 2: StagedBatch Model - Processing Progress Methods

**Files:**
- Modify: `app/models/staged_batch.rb`
- Test: `test/models/staged_batch_test.rb`

**Step 1: Write failing test for broadcast_processing_progress**

Add to `test/models/staged_batch_test.rb`:

```ruby
class StagedBatchProcessingProgressTest < ActiveSupport::TestCase
  setup do
    @batch = staged_batches(:processing_batch)
  end

  test "broadcast_processing_progress updates column and broadcasts" do
    mock_broadcast = Minitest::Mock.new
    mock_broadcast.expect(:call, nil, [@batch, { event: "processing_progress", progress: 50, status: "processing" }])

    StagedBatchChannel.stub(:broadcast_to, mock_broadcast) do
      @batch.broadcast_processing_progress(50)
    end

    assert_equal 50, @batch.reload.processing_progress
    mock_broadcast.verify
  end

  test "broadcast_processing_progress_if_needed only broadcasts on percentage change" do
    @batch.update_column(:processing_progress, 10)
    @batch.update_column(:processing_total, 100)

    broadcast_count = 0
    StagedBatchChannel.stub(:broadcast_to, ->(*) { broadcast_count += 1 }) do
      # Same percentage - should not broadcast
      @batch.broadcast_processing_progress_if_needed(10, 100)
      assert_equal 0, broadcast_count

      # Different percentage - should broadcast
      @batch.broadcast_processing_progress_if_needed(20, 100)
      assert_equal 1, broadcast_count
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /processing_progress/`

Expected: FAIL - methods not defined

**Step 3: Implement broadcast_processing_progress methods**

Add to `app/models/staged_batch.rb` in the private section, after `broadcast_completion`:

```ruby
  # Broadcasts processing progress to subscribed clients.
  # Failures are logged but don't interrupt the processing operation.
  #
  # @param progress [Integer] Progress percentage (0-100)
  def broadcast_processing_progress(progress)
    update_column(:processing_progress, progress)
    StagedBatchChannel.broadcast_to(self, {
      event: "processing_progress",
      progress: progress,
      status: status
    })
  rescue StandardError => e
    Rails.logger.warn "Failed to broadcast processing progress for batch #{id}: #{e.message}"
  end

  # Broadcasts processing progress if the percentage has changed.
  #
  # @param current [Integer] Current item index (0-based)
  # @param total [Integer] Total number of items
  def broadcast_processing_progress_if_needed(current, total)
    return if total.zero?

    new_progress = ((current.to_f / total) * 100).round
    return if new_progress == processing_progress
    return if (new_progress % PROGRESS_BROADCAST_INTERVAL != 0) && new_progress != 100

    broadcast_processing_progress(new_progress)
  end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/staged_batch_test.rb -n /processing_progress/`

Expected: PASS

**Step 5: Add fixture for processing batch if needed**

Check `test/fixtures/staged_batches.yml` and add if missing:

```yaml
processing_batch:
  id: <%= SecureRandom.uuid %>
  processor_type: "Processors::Aircraft::Aircraft"
  entity_type: "Aircraft"
  status: 0  # processing
  summary: { "created": 0, "updated": 0, "unchanged": 0 }
  processing_progress: 0
  processing_total: 100
  created_at: <%= Time.current %>
  updated_at: <%= Time.current %>
```

**Step 6: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb test/fixtures/staged_batches.yml
git commit -m "feat: add processing progress broadcast methods to StagedBatch"
```

---

## Task 3: Processors::Base - Hook Progress Bar to ActionCable

**Files:**
- Modify: `app/models/processors/base.rb`
- Test: `test/models/processors/base_test.rb`

**Step 1: Write failing test for progress broadcasting**

Add to `test/models/processors/base_test.rb`:

```ruby
class ProcessorsBaseProgressBroadcastTest < ActiveSupport::TestCase
  test "progress bar broadcasts to staged batch when in batch context" do
    batch = StagedBatch.create!(
      processor_type: "TestProcessor",
      entity_type: "Test",
      status: :processing,
      summary: { "created" => 0, "updated" => 0, "unchanged" => 0 }
    )

    Processors::Base.current_batch = batch

    progress_bar = Processors::Base.create_progress_bar(100)
    batch.update_column(:processing_total, 100)

    broadcast_count = 0
    StagedBatchChannel.stub(:broadcast_to, ->(*) { broadcast_count += 1 }) do
      # Increment enough to trigger a broadcast (1% = 1 item out of 100)
      progress_bar.increment!
    end

    assert_operator broadcast_count, :>=, 1
  ensure
    Processors::Base.current_batch = nil
    batch&.destroy
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb -n /progress.*broadcast/`

Expected: FAIL - no broadcasting happening

**Step 3: Create BroadcastingProgressBar wrapper class**

Add to `app/models/processors/base.rb` after the `NullProgressBar` class:

```ruby
    # A progress bar wrapper that broadcasts progress to ActionCable.
    # Wraps the real ProgressBar and broadcasts updates to the current batch.
    class BroadcastingProgressBar
      def initialize(total, batch)
        @total = total
        @batch = batch
        @current = 0
        @inner = if Processors::Base.interactive_console?
                   ProgressBar.new(total)
                 else
                   NullProgressBar.new(total)
                 end
      end

      def increment!
        @current += 1
        @inner.increment!
        @batch&.broadcast_processing_progress_if_needed(@current, @total)
      end

      def puts(*args)
        @inner.puts(*args)
      end

      def finish
        @inner.finish
      end
    end
```

**Step 4: Update create_progress_bar to use BroadcastingProgressBar**

Replace the `create_progress_bar` method:

```ruby
    # Creates a progress bar that optionally broadcasts to ActionCable.
    #
    # When called within a with_staged_batch block, progress updates are
    # broadcast to subscribed clients. Also stores the total in the batch.
    #
    # @param count [Integer] The total number of items to process
    # @return [BroadcastingProgressBar, NullProgressBar]
    def self.create_progress_bar(count)
      if current_batch
        current_batch.update_column(:processing_total, count)
        BroadcastingProgressBar.new(count, current_batch)
      elsif interactive_console?
        ProgressBar.new(count)
      else
        NullProgressBar.new(count)
      end
    end
```

**Step 5: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -n /progress.*broadcast/`

Expected: PASS

**Step 6: Run all processor tests to ensure no regressions**

Run: `./bin/rails test test/models/processors/`

Expected: All PASS

**Step 7: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "feat: broadcast processing progress via ActionCable"
```

---

## Task 4: JavaScript Controller - Extend for Processing + Fallback Polling

**Files:**
- Modify: `app/javascript/controllers/batch_apply_controller.js`

**Step 1: Add processing status handling to connect()**

Update the `connect()` method to handle both statuses:

```javascript
  connect() {
    if (this.statusValue === "applying" || this.statusValue === "processing") {
      this.showProgress()
      this.subscribe()
    }
  }
```

**Step 2: Update handleMessage to handle processing_progress event**

Update the `handleMessage` method:

```javascript
  handleMessage(data) {
    if (data.event === "progress" || data.event === "processing_progress") {
      this.updateProgress(data.progress, data.event)
    } else if (data.event === "complete") {
      this.handleComplete(data)
    }
  }
```

**Step 3: Update updateProgress to show correct label**

Update the `updateProgress` method:

```javascript
  updateProgress(progress, event = "progress") {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${progress}%`
    }
    if (this.hasProgressTextTarget) {
      const label = event === "processing_progress" ? "Processing" : "Applying"
      this.progressTextTarget.textContent = `${label}... ${progress}%`
    }

    // Start fallback polling when we hit 100%
    if (progress >= 100 && !this.pollingStarted) {
      this.startFallbackPolling()
    }
  }
```

**Step 4: Add fallback polling methods**

Add these new methods:

```javascript
  /**
   * Starts polling the batch status as a fallback in case
   * the ActionCable completion event is missed.
   */
  startFallbackPolling() {
    this.pollingStarted = true
    this.pollInterval = setInterval(() => this.checkBatchStatus(), 2000)
  }

  /**
   * Fetches the current batch status and reloads if complete.
   */
  async checkBatchStatus() {
    try {
      const response = await fetch(`/admin/staged_batches/${this.batchIdValue}/status.json`)
      const data = await response.json()

      if (data.status !== "applying" && data.status !== "processing") {
        this.stopPolling()
        window.location.reload()
      }
    } catch (error) {
      console.error("Failed to check batch status:", error)
    }
  }

  /**
   * Stops the fallback polling interval.
   */
  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }
```

**Step 5: Update disconnect to clean up polling**

Update the `disconnect` method:

```javascript
  disconnect() {
    this.stopPolling()
    this.unsubscribe()
  }
```

**Step 6: Commit**

```bash
git add app/javascript/controllers/batch_apply_controller.js
git commit -m "feat: extend batch controller for processing progress + fallback polling"
```

---

## Task 5: Add Status Endpoint for Fallback Polling

**Files:**
- Modify: `app/controllers/admin/staged_batches_controller.rb`
- Modify: `config/routes.rb`

**Step 1: Add status action to controller**

Add to `app/controllers/admin/staged_batches_controller.rb`:

```ruby
  # GET /admin/staged_batches/:id/status
  # Returns JSON status for fallback polling
  def status
    @batch = StagedBatch.find(params[:id])
    render json: {
      status: @batch.status,
      processing_progress: @batch.processing_progress,
      apply_progress: @batch.apply_progress
    }
  end
```

**Step 2: Add route**

Add to `config/routes.rb` inside the staged_batches resource:

```ruby
resources :staged_batches, only: [:index, :show] do
  member do
    post :apply
    post :reject
    post :rollback
    get :status  # Add this line
  end
end
```

**Step 3: Commit**

```bash
git add app/controllers/admin/staged_batches_controller.rb config/routes.rb
git commit -m "feat: add status endpoint for batch polling fallback"
```

---

## Task 6: Staged Batch Show - Processing Progress Bar

**Files:**
- Modify: `app/views/admin/staged_batches/show.html.erb`

**Step 1: Update status check to include processing**

Find the progress indicator section (around line 84-99) and update it to handle both statuses.

Replace:
```erb
        <%# Progress indicator (shown when applying) %>
        <div data-batch-apply-target="progress"
             class="w-64 <%= 'hidden' unless @batch.applying? %>">
          <div class="text-sm font-medium text-gray-700 mb-2"
               data-batch-apply-target="progressText">
            Applying... <%= @batch.apply_progress %>%
          </div>
```

With:
```erb
        <%# Progress indicator (shown when processing or applying) %>
        <div data-batch-apply-target="progress"
             class="w-64 <%= 'hidden' unless @batch.applying? || @batch.processing? %>">
          <div class="text-sm font-medium text-gray-700 mb-2"
               data-batch-apply-target="progressText">
            <%= @batch.processing? ? "Processing" : "Applying" %>... <%= @batch.processing? ? @batch.processing_progress : @batch.apply_progress %>%
          </div>
```

**Step 2: Update progress bar width**

Replace:
```erb
                 style="width: <%= @batch.apply_progress %>%"></div>
```

With:
```erb
                 style="width: <%= @batch.processing? ? @batch.processing_progress : @batch.apply_progress %>%"></div>
```

**Step 3: Update total count display**

Replace:
```erb
          <div class="text-xs text-gray-500 mt-1">
            Processing <%= @batch.apply_total || @batch.staged_changes.count %> changes
          </div>
```

With:
```erb
          <div class="text-xs text-gray-500 mt-1">
            <% if @batch.processing? %>
              Processing <%= @batch.processing_total || "..." %> records
            <% else %>
              Processing <%= @batch.apply_total || @batch.staged_changes.count %> changes
            <% end %>
          </div>
```

**Step 4: Update actions visibility for processing**

Replace:
```erb
        <div data-batch-apply-target="actions"
             class="flex gap-2 <%= 'hidden' if @batch.applying? %>">
```

With:
```erb
        <div data-batch-apply-target="actions"
             class="flex gap-2 <%= 'hidden' if @batch.applying? || @batch.processing? %>">
```

**Step 5: Commit**

```bash
git add app/views/admin/staged_batches/show.html.erb
git commit -m "feat: show processing progress bar on batch show page"
```

---

## Task 7: Staged Batches Index - Compact Progress Indicators

**Files:**
- Modify: `app/views/admin/staged_batches/_batch.html.erb`

**Step 1: Update status cell to show progress for active batches**

Replace the status cell (lines 5-8):

```erb
  <td class="whitespace-nowrap px-3 py-4 text-sm">
    <span class="<%= status_badge_classes(batch.status) %>">
      <%= batch.status.titleize %>
    </span>
  </td>
```

With:

```erb
  <td class="whitespace-nowrap px-3 py-4 text-sm"
      data-controller="<%= batch.processing? || batch.applying? ? 'batch-apply' : '' %>"
      data-batch-apply-batch-id-value="<%= batch.id %>"
      data-batch-apply-status-value="<%= batch.status %>">
    <% if batch.processing? %>
      <div class="flex items-center gap-2">
        <svg class="animate-spin h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="text-indigo-600" data-batch-apply-target="progressText">Processing <%= batch.processing_progress %>%</span>
      </div>
    <% elsif batch.applying? %>
      <div class="flex items-center gap-2">
        <svg class="animate-spin h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="text-indigo-600" data-batch-apply-target="progressText">Applying <%= batch.apply_progress %>%</span>
      </div>
    <% else %>
      <span class="<%= status_badge_classes(batch.status) %>">
        <%= batch.status.titleize %>
      </span>
    <% end %>
  </td>
```

**Step 2: Commit**

```bash
git add app/views/admin/staged_batches/_batch.html.erb
git commit -m "feat: show compact progress indicators on batches index"
```

---

## Task 8: Processors Index - Running Status with Progress

**Files:**
- Modify: `app/views/admin/processors/index.html.erb`
- Modify: `app/controllers/admin/processors_controller.rb`

**Step 1: Check controller provides processing batch**

Verify `app/controllers/admin/processors_controller.rb` provides the processing batch info. The `@processors` array should already include `:processing` and `:last_batch` for each processor.

**Step 2: Update the status/action cell in processors index**

Replace lines 48-57:

```erb
              <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
                <% if processor[:processing] %>
                  <span class="text-gray-400">Running...</span>
                <% else %>
                  <%= button_to "Run",
                                admin_processors_path(entity_type: processor[:entity_type]),
                                method: :post,
                                class: "rounded-md bg-indigo-600 px-2.5 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
                                data: { turbo_confirm: "Run #{processor[:entity_type]} processor?" } %>
                <% end %>
              </td>
```

With:

```erb
              <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
                <% if processor[:processing] %>
                  <div class="flex items-center justify-end gap-2"
                       data-controller="batch-apply"
                       data-batch-apply-batch-id-value="<%= processor[:processing_batch]&.id %>"
                       data-batch-apply-status-value="processing">
                    <svg class="animate-spin h-4 w-4 text-indigo-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span class="text-indigo-600" data-batch-apply-target="progressText">
                      <%= processor[:processing_batch]&.processing_progress || 0 %>%
                    </span>
                    <% if processor[:processing_batch] %>
                      <%= link_to "View", admin_staged_batch_path(processor[:processing_batch]), class: "text-indigo-600 hover:text-indigo-900 ml-2" %>
                    <% end %>
                  </div>
                <% else %>
                  <%= button_to "Run",
                                admin_processors_path(entity_type: processor[:entity_type]),
                                method: :post,
                                class: "rounded-md bg-indigo-600 px-2.5 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
                                data: { turbo_confirm: "Run #{processor[:entity_type]} processor?" } %>
                <% end %>
              </td>
```

**Step 3: Update controller to provide processing_batch**

Update `app/controllers/admin/processors_controller.rb` to include the processing batch in the data:

Find where `@processors` is built and ensure each processor hash includes:
```ruby
processing_batch: StagedBatch.processing.find_by(entity_type: entity_type)
```

**Step 4: Commit**

```bash
git add app/views/admin/processors/index.html.erb app/controllers/admin/processors_controller.rb
git commit -m "feat: show processing progress on processors index"
```

---

## Task 9: Home Controller - Add Pending Batches Query

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Test: `test/controllers/home_controller_test.rb`

**Step 1: Write failing test**

Add to `test/controllers/home_controller_test.rb`:

```ruby
class HomeControllerDashboardTest < ActionDispatch::IntegrationTest
  test "dashboard loads pending batches" do
    # Create a pending batch
    batch = StagedBatch.create!(
      processor_type: "TestProcessor",
      entity_type: "Test",
      status: :pending,
      summary: { "created" => 5, "updated" => 3, "unchanged" => 0 }
    )

    get dashboard_path

    assert_response :success
    assert_select "a[href='#{admin_staged_batch_path(batch)}']"
  ensure
    batch&.destroy
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/controllers/home_controller_test.rb -n /pending_batches/`

Expected: FAIL - no link to batch

**Step 3: Add pending batches query to dashboard action**

Update `app/controllers/home_controller.rb`:

```ruby
  def dashboard
    @aircraft_count = Aircraft.count
    @aircraft_types_count = AircraftType.count
    @manufacturers_count = Manufacturer.count
    @airports_count = Airport.count
    @countries_count = Country.count
    @routes_count = Route.count
    @operators_count = Operator.count

    # Pending approvals widget
    @pending_batches = StagedBatch.pending.order(created_at: :desc).limit(5).includes(:created_by)
    @pending_count = StagedBatch.pending.count
  end
```

**Step 4: Commit**

```bash
git add app/controllers/home_controller.rb test/controllers/home_controller_test.rb
git commit -m "feat: add pending batches query to dashboard"
```

---

## Task 10: Dashboard - Replace Pending Approvals Widget

**Files:**
- Modify: `app/views/home/dashboard.html.erb`

**Step 1: Replace the prototype widget**

Replace lines 265-350 (the entire Pending Approvals Panel) with:

```erb
  <!-- Pending Approvals Panel -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-4 py-5 sm:p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg leading-6 font-medium text-gray-900">Pending Approvals</h3>
        <div class="flex items-center">
          <% if @pending_count > 0 %>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
              <%= @pending_count %> pending
            </span>
          <% end %>
        </div>
      </div>
      <div class="space-y-3">
        <% if @pending_batches.any? %>
          <% @pending_batches.each do |batch| %>
            <div class="flex items-start justify-between py-2 border-b border-gray-100 last:border-b-0">
              <div class="flex items-start space-x-3">
                <div class="size-2 bg-orange-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900"><%= batch.entity_type %></p>
                  <p class="text-sm text-gray-500">
                    <%= batch.summary["created"].to_i %> created,
                    <%= batch.summary["updated"].to_i %> updated,
                    <%= batch.summary["unchanged"].to_i %> unchanged
                  </p>
                  <p class="text-xs text-gray-400">
                    by <%= batch.created_by&.name || "System" %> · <%= time_ago_in_words(batch.created_at) %> ago
                  </p>
                </div>
              </div>
              <div>
                <%= link_to "Review",
                            admin_staged_batch_path(batch),
                            class: "inline-flex items-center px-2 py-1 border border-transparent rounded text-xs font-medium text-purple-700 bg-purple-100 hover:bg-purple-200" %>
              </div>
            </div>
          <% end %>
        <% else %>
          <p class="text-sm text-gray-500 text-center py-4">No pending approvals</p>
        <% end %>
      </div>
      <% if @pending_count > 5 %>
        <div class="mt-4">
          <%= link_to admin_staged_batches_path(status: "pending"), class: "text-sm text-purple-600 hover:text-purple-800 font-medium" do %>
            View all <%= @pending_count %> pending approvals
            <span aria-hidden="true"> &rarr;</span>
          <% end %>
        </div>
      <% elsif @pending_count > 0 %>
        <div class="mt-4">
          <%= link_to admin_staged_batches_path(status: "pending"), class: "text-sm text-purple-600 hover:text-purple-800 font-medium" do %>
            View all pending approvals
            <span aria-hidden="true"> &rarr;</span>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>
```

**Step 2: Verify test passes**

Run: `./bin/rails test test/controllers/home_controller_test.rb`

Expected: PASS

**Step 3: Commit**

```bash
git add app/views/home/dashboard.html.erb
git commit -m "feat: replace prototype pending approvals with real data"
```

---

## Task 11: Final Testing and Documentation

**Step 1: Run full test suite**

Run: `./bin/rails test`

Expected: All tests pass

**Step 2: Manual testing checklist**

- [ ] Trigger a processor and verify progress appears on processors index
- [ ] Navigate to staged batch show page while processing - verify progress bar
- [ ] Check staged batches index shows progress for processing/applying batches
- [ ] Complete an apply and verify page reloads (via event or fallback polling)
- [ ] Check dashboard pending approvals widget shows real data

**Step 3: Update README if needed**

Add any relevant documentation about the new progress tracking features.

**Step 4: Final commit**

```bash
git add -A
git commit -m "docs: update documentation for processor UI improvements"
```
