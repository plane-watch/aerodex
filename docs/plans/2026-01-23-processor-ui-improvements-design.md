# Processor UI Improvements Design

## Overview

Three related improvements to processor and staged batch UI:

1. Add progress tracking to processor "processing" jobs (matching existing "apply" progress)
2. Fix bug where apply completion doesn't refresh the page
3. Replace prototype pending approvals widget with real data

## 1. Processing Progress Tracking

### Architecture

Hook into existing Ruby ProgressBar infrastructure to broadcast progress via ActionCable.

### Database Changes

Add to `staged_batches` table:
- `processing_progress` (integer, default: 0) - Current progress 0-100%
- `processing_total` (integer) - Total records to process

### Model Changes (StagedBatch)

Add methods mirroring existing apply progress:

```ruby
def broadcast_processing_progress(progress)
  update_column(:processing_progress, progress)
  StagedBatchChannel.broadcast_to(self, { type: "processing_progress", progress: progress })
end

def broadcast_processing_progress_if_needed(current, total)
  new_progress = ((current.to_f / total) * 100).round
  return if new_progress == processing_progress
  broadcast_processing_progress(new_progress)
end
```

### Processor Changes (Base)

Modify `create_progress_bar` or wrap increment logic to:
1. Store total in `staged_batch.processing_total` at start
2. On each increment, call `staged_batch.broadcast_processing_progress_if_needed(current, total)`

No changes needed to individual processor implementations - they all use the base infrastructure.

### ActionCable

Extend existing `StagedBatchChannel` to handle new event type `"processing_progress"`.

## 2. Progress UI Components

### Staged Batch Show Page

When status is `processing`:
- Show progress bar identical to apply progress bar
- Text: "Processing... X%"
- Same indigo styling

### Staged Batches Index Page

For batches in `processing` or `applying` status:
- Replace status badge with compact progress indicator
- Small progress bar or percentage with spinner
- e.g., "Processing 45%" or "Applying 78%"
- Real-time updates via ActionCable subscription

### Processors Index Page

For processor with active (processing) batch:
- Show spinner + progress percentage
- Link to the batch: "Running: 45% (view batch)"
- Requires query to find batch by processor type

### JavaScript

Extend `batch_apply_controller.js` to `batch_progress_controller.js`:
- Handle both `processing_progress` and `progress` (apply) events
- Same ActionCable subscription pattern
- Different UI targets based on data attributes

## 3. Completion Bug Fix

### Problem

Apply finishes at 100% but page never reloads - completion event not received.

### Investigation

1. Verify `broadcast_completion` is called (add logging)
2. Check event type matches between Ruby broadcast and JS handler
3. Check if ActionCable connection drops during long jobs

### Solution

1. Fix root cause if found in investigation
2. Add fallback polling: when progress hits 100%, start polling batch status every 2 seconds, reload when status changes from `applying`

This belt-and-suspenders approach ensures reliability even with ActionCable issues.

## 4. Pending Approvals Widget

### Replace Prototype

Remove:
- "Prototype" badge
- Hardcoded mock data
- Non-functional approve/reject buttons

### Query

```ruby
# HomeController#dashboard
@pending_batches = StagedBatch.pending.order(created_at: :desc).limit(5).includes(:user)
@pending_count = StagedBatch.pending.count
```

### Display Per Batch

- Processor type (e.g., "Aircraft Types")
- Change breakdown: "12 created, 5 updated, 0 unchanged" (from `summary` JSON)
- Who triggered: "by #{batch.user.name}"
- Relative time: "2 hours ago"
- Link to batch show page

### Widget Header

- Title with count: "Pending Approvals (X)"
- "View all" link to `/admin/staged_batches?status=pending`

## Files to Modify

| File | Changes |
|------|---------|
| `db/migrate/xxx_add_processing_progress_to_staged_batches.rb` | Add `processing_progress` and `processing_total` columns |
| `app/models/staged_batch.rb` | Add broadcast methods for processing progress |
| `app/models/processors/base.rb` | Hook ProgressBar into ActionCable broadcasts |
| `app/javascript/controllers/batch_apply_controller.js` | Extend for processing events, add fallback polling |
| `app/views/admin/staged_batches/show.html.erb` | Add processing progress bar section |
| `app/views/admin/staged_batches/index.html.erb` | Add compact progress indicators for processing/applying |
| `app/views/admin/processors/index.html.erb` | Add running status indicator |
| `app/views/home/dashboard.html.erb` | Replace prototype widget with real data |
| `app/controllers/home_controller.rb` | Add pending batches query |

## Testing

- Test processing progress broadcasts correctly during processor run
- Test progress UI updates in real-time on all three pages
- Test completion triggers page reload (both via event and fallback polling)
- Test pending approvals widget shows correct data and counts
