# Staged Diffs for Batch ActiveRecord Changes

**Status:** Draft
**Date:** 2026-01-18
**Author:** Tim (with Claude)

## Problem Summary

Aerodex processors (e.g., `Processors::Aircraft::Aircraft`, `Processors::Operator::Operator`) aggregate data from multiple external sources into canonical records. Currently, these processors apply changes directly to the database using `insert_all`/`upsert_all`, making changes difficult to:

- Inspect before committing
- Audit after the fact
- Roll back selectively
- Approve or reject as a single logical operation

## Goals

Introduce a staging layer for data changes that:

1. **Preview before commit** - Capture intended changes (diffs) before they touch production data
2. **Review and approve** - Allow admins (including non-technical contributors) to review and approve/reject batches via a web UI
3. **Audit trail** - Maintain a durable record of what was planned, who approved it, and when it was applied
4. **Rollback capability** - Enable reversing applied batches when issues are discovered

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Diff granularity | Record-level (JSON blob per record) | Balance between storage efficiency and reviewability |
| Staging mode | Always stage | Consistent workflow; no changes bypass review |
| Pending batch conflicts | Block or supersede (TBD) | Either prevents confusion from stale batches |
| Apply strategy | Atomic transaction | Fail-safe; matches "fix and re-run" philosophy |
| Stale data handling | Fail if record modified since staging | Prevents silent overwrites of external changes |
| Rollback depth | Single-level (extensible later) | Keeps initial implementation simple |
| PaperTrail relationship | Disabled for batch ops | Staged diffs handle batch audit; PaperTrail handles manual edits |

---

## Data Model

### `staged_batches`

Represents a processor run's pending changes.

| Column | Type | Purpose |
|--------|------|---------|
| `id` | uuid | Primary key |
| `processor_type` | string | e.g., `"Processors::Aircraft::Aircraft"` |
| `entity_type` | string | e.g., `"Aircraft"`, `"Operator"` - for grouping/filtering |
| `status` | enum | `pending`, `approved`, `applied`, `rejected`, `superseded`, `rolled_back` |
| `summary` | jsonb | Counts: `{ created: 423, updated: 87, unchanged: 12045 }` |
| `created_by_id` | references | User who triggered the run (nullable for scheduled jobs) |
| `reviewed_by_id` | references | User who approved/rejected |
| `applied_at` | timestamp | When changes were committed |
| `reviewed_at` | timestamp | When approved/rejected |
| `notes` | text | Optional reviewer comments |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

**Indexes:**
- `status` (for filtering pending batches)
- `entity_type` (for filtering by model type)
- `created_at` (for ordering)

### `staged_changes`

Individual record diffs within a batch.

| Column | Type | Purpose |
|--------|------|---------|
| `id` | bigint | Primary key |
| `staged_batch_id` | references | Parent batch (foreign key) |
| `record_type` | string | Polymorphic: `"Aircraft"`, `"Operator"` |
| `record_id` | bigint | ID of existing record (null for creates) |
| `record_identifier` | string | Human-readable key, e.g., ICAO `"7C1469"` |
| `operation` | enum | `create`, `update` |
| `diff` | jsonb | `{ "registration": ["VH-OLD", "VH-NEW"], "owner": [null, "Qantas"] }` |
| `created_at` | timestamp | |

**Indexes:**
- `staged_batch_id` (for loading changes by batch)
- `record_type, record_id` (for lookups)

---

## Processor Integration

### Current Flow

```
gather sources → merge fields → validate → insert_all/upsert_all → done
```

### New Flow

```
gather sources → merge fields → validate → stage_change() → done
```

A `StagedBatch` is created at the start of the run. Each change is written as a `StagedChange` row. Summary counts are updated at the end.

### Changes to `Processors::Base`

New methods added to the base class:

#### `with_staged_batch`

Wraps a processor run. Creates the `StagedBatch` record, yields to the processing block, finalises summary counts.

```ruby
def self.with_staged_batch(entity_type:, &block)
  check_pending_batch!(entity_type)

  @current_batch = StagedBatch.create!(
    processor_type: name,
    entity_type: entity_type,
    status: :pending,
    summary: { created: 0, updated: 0, unchanged: 0 }
  )

  yield

  @current_batch.update!(summary: @batch_summary)
  @current_batch
ensure
  @current_batch = nil
end
```

#### `stage_change(record, operation:, identifier:)`

Replaces direct `insert_all`/`upsert_all` calls. Computes the diff and writes a `StagedChange` row.

```ruby
def self.stage_change(record, operation:, identifier:)
  diff = case operation
         when :create
           record.attributes.transform_values { |v| [nil, v] }
         when :update
           record.changes
         end

  @current_batch.staged_changes.create!(
    record_type: record.class.name,
    record_id: record.id,
    record_identifier: identifier,
    operation: operation,
    diff: diff
  )

  @batch_summary[operation == :create ? :created : :updated] += 1
end
```

#### `check_pending_batch!(entity_type)`

Called at start of run. Handles existing pending batches.

```ruby
def self.check_pending_batch!(entity_type)
  pending = StagedBatch.pending.where(entity_type: entity_type).first
  return unless pending

  # Option A: Block
  raise "Pending batch exists for #{entity_type}. Approve or reject before re-running."

  # Option B: Supersede
  # pending.update!(status: :superseded)
end
```

### Processor Modifications

Minimal changes required to existing processors:

1. Replace `flush_inserts(records)` / `flush_updates(records)` with calls to `stage_change`
2. Wrap the main processing loop in `with_staged_batch do ... end`
3. Remove direct `insert_all` / `upsert_all` calls

Validation stays exactly where it is - records are validated before staging.

---

## Apply Process

When an admin approves a batch, `StagedBatch#apply!` executes:

1. **Guard checks**
   - Raise error if batch isn't `pending`
   - Raise error if a newer batch for this entity type has already been applied
   - Check for stale data: if any target record has `updated_at > batch.created_at`, abort

2. **Wrap in transaction** - Single atomic transaction for the entire batch

3. **Group changes by operation** - Separate creates from updates

4. **Build attribute hashes**
   - Creates: Build full attribute hash from diff (new values)
   - Updates: Apply diff values to current record state

5. **Execute bulk operations**
   ```ruby
   Model.insert_all(create_attributes)
   Model.upsert_all(update_attributes, unique_by: :id)
   ```

6. **Post-apply hooks** - Reindex Meilisearch, reset counter caches (same as current `finalize_combine`)

7. **Update batch status**
   ```ruby
   update!(status: :applied, applied_at: Time.current, reviewed_by: current_user)
   ```

PaperTrail remains disabled during apply (via `with_bulk_import`) since staged changes serve as the audit trail.

---

## Rollback Process

When an admin needs to undo an applied batch, `StagedBatch#rollback!` executes:

1. **Guard checks**
   - Only `applied` batches can be rolled back
   - Cannot rollback if a newer batch for this entity type has been applied

2. **Generate inverse diffs**
   - Creates → Deletes: Collect IDs of created records
   - Updates → Reverse updates: Swap old ↔ new values in diff

3. **Wrap in transaction** - Atomic, same as apply

4. **Execute reversals**
   ```ruby
   Model.where(id: created_ids).delete_all
   Model.upsert_all(reverse_attributes, unique_by: :id)
   ```

5. **Post-rollback hooks** - Reindex, reset counter caches

6. **Update batch status**
   ```ruby
   update!(status: :rolled_back, reviewed_by: current_user, reviewed_at: Time.current)
   ```

Original `StagedChange` records remain untouched for audit purposes.

---

## Admin Web UI

### Routes

```ruby
namespace :admin do
  resources :staged_batches, only: [:index, :show] do
    member do
      post :apply
      post :reject
      post :rollback
    end
  end
end
```

### Index View (`/admin/staged_batches`)

- Filterable by status and entity type
- Table columns: Entity Type, Status, Summary, Created At, Reviewed By
- Pending batches highlighted and sorted to top
- Visual badge showing pending count

### Show View (`/admin/staged_batches/:id`)

- **Header**: Batch metadata, status, timestamps
- **Action buttons**: Approve & Apply, Reject (with notes field), Rollback (for applied batches)
- **Summary panel**: Counts of creates/updates/unchanged
- **Diff browser**:
  - Paginated list of `StagedChanges`
  - Grouped by operation type
  - Each row shows: record identifier, operation, expandable diff detail
  - Diff displayed as old → new for each changed field
  - Search/filter within the batch

---

## Notifications

### Phase 1 (MVP)

- **UI badge**: Admin nav shows count of pending batches
- **Email**: After processor run, send email to configured recipients with summary and link

### Phase 2 (Later)

- **Discord webhook**: POST summary to configured channel
- **Scheduled digest**: Daily/weekly summary instead of per-batch emails

### Implementation

- `after_commit` callback on `StagedBatch` triggers notifications
- Email via `deliver_later` (async)
- Configuration via environment variables or simple settings model

---

## Console & Rake Interface

### Rake Tasks

```bash
# List pending batches
rake staged_batches:pending

# Show batch details
rake staged_batches:show[BATCH_ID]

# Apply a batch
rake staged_batches:apply[BATCH_ID]

# Reject a batch
rake staged_batches:reject[BATCH_ID]

# Rollback an applied batch
rake staged_batches:rollback[BATCH_ID]

# List recent batches (all statuses)
rake staged_batches:history[LIMIT]
```

### Rails Console

```ruby
# Find pending batches
StagedBatch.pending

# Inspect a batch
batch = StagedBatch.find(id)
batch.summary
batch.staged_changes.limit(5)

# Apply/reject/rollback
batch.apply!(by: current_user)
batch.reject!(reason: "Model matching bug")
batch.rollback!(by: current_user)

# Processor runs return the batch
batch = Processors::Aircraft::Aircraft.combine_sources
batch.pending?  # => true
```

### Useful Scopes

```ruby
class StagedBatch
  scope :pending, -> { where(status: :pending) }
  scope :applied, -> { where(status: :applied) }
  scope :rejected, -> { where(status: :rejected) }
  scope :for_entity, ->(type) { where(entity_type: type) }
  scope :recent, -> { order(created_at: :desc) }
end
```

---

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create migrations for `staged_batches` and `staged_changes` tables
- [ ] Create `StagedBatch` model with validations, associations, status enum
- [ ] Create `StagedChange` model with validations, associations
- [ ] Add scopes (`.pending`, `.applied`, `.for_entity`, etc.)
- [ ] Write model specs

### Phase 2: Processor Integration
- [ ] Add staging methods to `Processors::Base`
- [ ] Refactor `Processors::Operator::Operator` to use staging (smaller, good test case)
- [ ] Test stage → apply cycle via console
- [ ] Refactor `Processors::Aircraft::Aircraft`
- [ ] Refactor remaining processors as needed

### Phase 3: Console/Rake Tools
- [ ] Create rake tasks (pending, show, apply, reject)
- [ ] Validate end-to-end workflow via CLI
- [ ] Document rake task usage

### Phase 4: Admin Web UI
- [ ] Create `Admin::StagedBatchesController`
- [ ] Create index view with filtering
- [ ] Create show view with diff browser
- [ ] Implement apply/reject actions
- [ ] Add pending batch count to admin nav

### Phase 5: Notifications
- [ ] Add email notification on batch creation
- [ ] Add UI badge for pending count
- [ ] (Optional) Add Discord webhook integration

### Phase 6: Rollback
- [ ] Implement `StagedBatch#rollback!`
- [ ] Add rollback rake task
- [ ] Add rollback button to UI (for applied batches)

---

## Open Questions

1. **Block vs Supersede**: When a processor runs with a pending batch already exists, should we block the run or automatically supersede the old batch?

2. **Batch expiry**: Should pending batches auto-expire after N days? Or remain indefinitely until actioned?

3. **Permissions**: Should all admins be able to approve/reject, or do we need role-based access?

---

## Future Considerations

- **Multi-level rollback**: Generate reversal batches instead of direct rollback, allowing rollback-of-rollback
- **Partial apply**: Approve/reject individual changes within a batch (currently all-or-nothing)
- **CI/CD integration**: Trigger processor runs from CI, auto-approve in staging environments
- **Diff size limits**: For very large batches, consider chunking or streaming the diff browser
