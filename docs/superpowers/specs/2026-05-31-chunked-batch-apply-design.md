# Chunked Staged-Batch Apply Design

**Date:** 2026-05-28
**Status:** Approved design, pending implementation plan

## Purpose

Applying a staged batch currently runs every staged change inside a single
database transaction (`StagedBatch#apply!`). For a large batch — e.g. ~600k
route changes from the VRS route importer — this causes three problems:

1. **Progress appears frozen.** `apply_progress` is written with `update_column`
   *inside* the one wrapping transaction, so the column change is invisible to
   other database connections (the UI's polling fallback) until the whole
   transaction commits. The bar effectively jumps from 0% to 100%.
2. **One enormous transaction.** Holding a single transaction open across 600k
   row writes means long-held locks, large memory/WAL growth, and degrading
   performance as the transaction grows.
3. **All-or-nothing rollback.** A failure at row 599,999 discards every change,
   forcing a complete restart with no record of progress.

This design replaces the single transaction with chunked, committed batches that
report visible progress and can resume after a failure.

## Scope

### In scope
- `StagedBatch#apply!` and its private apply loop (`apply_changes!`).
- A new `staged_changes.applied_at` column to track per-change completion.
- The `apply!` status guard, to allow resuming a `failed`/`applying` batch.

### Out of scope
- **The combine phase.** `Processors::Route::Route.combine_sources` (and other
  combiners) already use `find_each` and broadcast progress per record, with each
  `staged_changes.create!` committing independently. It is not a single
  transaction and is not changed here.
- **`apply_single_change` semantics.** How an individual create/update is applied
  (including nested route segments) is unchanged.
- **The stale-data check semantics**, the ActionCable broadcasts, and the
  progress-throttling behaviour are unchanged (only *where* they run moves).
- **A "run again" UI affordance.** Re-running a processor to produce a fresh
  batch is the existing, separate flow (see "Resume versus run again").

## Background: current behaviour

`StagedBatch#apply!` (`app/models/staged_batch.rb`):

```ruby
def apply!(by:)
  raise InvalidStatusError unless pending? || applying?
  raise ApplyError if staged_changes.empty?

  transaction do                 # one transaction wrapping everything
    check_for_stale_data!
    apply_changes!               # find_each over all changes, broadcast per 1%
    self.status = :applied
    # ... apply_progress = 100; save!
  end

  broadcast_completion
  run_post_apply_hooks
rescue StandardError => e
  update!(status: :failed, error_message: ..., apply_progress: 0)
  broadcast_completion
  raise
end
```

`apply_changes!` calls `apply_single_change` then `broadcast_progress_if_needed`,
which does `update_column(:apply_progress, ...)` — invisible to other connections
until the outer transaction commits.

The admin controller already sets `status: :applying`, `apply_progress: 0` and
`apply_total: staged_changes.count` before enqueuing `ApplyBatchJob`, and the UI
(`batch_apply_controller.js`) listens on `StagedBatchChannel` with a DB-polling
fallback — so committing progress per chunk is what makes the bar advance
reliably.

## Design

### 1. Per-change completion marker

Add a nullable `applied_at :datetime` column to `staged_changes`, with a
composite index `(staged_batch_id, applied_at)` to make "the unapplied changes
for this batch" an indexed lookup.

`applied_at` is the single source of truth for what has been applied. It is set
*in the same transaction* as the change it marks, so a committed chunk always has
its records and their markers consistent.

### 2. Chunked apply loop

Replace the single wrapping transaction with a loop over unapplied changes in
chunks of `APPLY_BATCH_SIZE` (1000):

```ruby
APPLY_BATCH_SIZE = 1000

def apply_changes!
  remaining = staged_changes.where(applied_at: nil).order(:id)
  applied = staged_changes.where.not(applied_at: nil).count

  remaining.find_each(batch_size: APPLY_BATCH_SIZE).each_slice(APPLY_BATCH_SIZE) do |chunk|
    transaction do
      chunk.each do |change|
        apply_single_change(change)
        change.update_column(:applied_at, Time.current)
      end
    end
    applied += chunk.size
    update_apply_progress(applied)   # own committed write + broadcast, visible to pollers
  end
end
```

(The exact slicing mechanism is a plan detail; the contract is: each chunk is one
committed transaction that both applies its changes and marks their `applied_at`.)

### 3. `apply!` flow

```ruby
def apply!(by:)
  raise InvalidStatusError unless pending? || applying? || failed?  # failed => resumable
  raise ApplyError if staged_changes.empty?

  start_apply!          # status :applying, apply_total set once, initial progress committed & broadcast
  check_for_stale_data! # over the unapplied UPDATE changes only
  apply_changes!        # chunked, each chunk its own committed transaction
  finish_apply!(by)     # status :applied, applied_at/reviewed_by, apply_progress 100, save!

  broadcast_completion
  run_post_apply_hooks
rescue StandardError => e
  mark_failed!(e)       # status :failed, error_message; apply_progress reflects committed work (NOT reset to 0)
  broadcast_completion
  raise
end
```

Key changes from today:
- No single wrapping transaction; each chunk commits independently.
- `apply_total` is set once at the start (removing the per-iteration
  `staged_changes.count` fallback).
- On failure, `apply_progress` is **not** reset to 0 — it reflects the chunks that
  did commit, so the UI shows true partial progress.
- The guard allows `failed` (and `applying`) so a stalled apply can resume.

### 4. Failure and resume

If a chunk raises, that chunk's transaction rolls back — neither its record
writes nor its `applied_at` markers persist — while earlier committed chunks
remain. The batch is marked `:failed` with the error message.

Re-invoking `apply!` resumes: `start_apply!` flips it back to `:applying`,
`apply_changes!` selects only `applied_at IS NULL` changes, and processing
continues from where it stopped. Because completed changes are skipped, resume is
idempotent — no create is run twice.

### Resume versus run again (kept separate)

These are two distinct operations and are never conflated:

- **Resume** — call `apply!` on the *same* failed batch. It continues applying the
  remaining `applied_at IS NULL` changes. `apply!` never restarts an
  already-applied change.
- **Run again** — the existing, separate flow: run the processor again
  (`combine_sources`), which creates a *new* `StagedBatch`. A `failed` batch is not
  `pending`, so `check_pending_batch!` does not block a fresh run; and the combine
  compares against current database state, so any partially-applied records are
  simply seen as already present.

There is no automatic "start over": `apply!` only ever moves forward over
unapplied changes.

## Error handling

- A failing chunk rolls back only that chunk; the batch becomes `:failed` with
  `error_message`, retaining committed progress for a later resume.
- `apply_single_change` keeps its existing enriched `RecordInvalid` context so the
  failing record is identifiable in the error message.
- The stale-data check runs once per `apply!` invocation over the unapplied update
  changes; on resume it re-checks only what remains.
- Broadcast failures continue to be logged and swallowed (unchanged).

## Testing strategy (TDD)

- **Happy path:** a batch of N changes applies fully → status `applied`,
  `apply_progress` 100, every `applied_at` set, target records present.
- **Chunked commit + resume:** with a small `APPLY_BATCH_SIZE`, force a failure in
  the second chunk (e.g. one change that raises). Assert: first chunk's records
  are committed and their `applied_at` set, status `failed`, `apply_progress`
  reflects only the committed chunk; then re-invoke `apply!` and assert it
  completes, status `applied`, with no duplicated creates (resume + idempotency).
- **Idempotent no-op:** applying a batch whose changes are all `applied_at`-marked
  finalises status without re-applying anything.
- **Stale data:** an update whose target was modified after the batch was created
  still raises `StaleDataError`.
- **Progress visibility:** `apply_total` is set once; `apply_progress` advances per
  chunk (assert the column is updated between chunks rather than only at the end).

## Key decisions and rationale

| Decision | Rationale |
|---|---|
| Chunked transactions (commit per 1000) | Bounds lock/WAL/memory; makes committed progress visible to pollers. |
| `applied_at` per change | Explicit, robust completion marker enabling safe resume and idempotency. |
| Marker set in the change's own transaction | Guarantees records and their "done" flag commit together. |
| `failed` is resumable via `apply!` | User-approved; the `applied_at` markers make re-runs safe. |
| Resume and run-again kept as separate entry points | `apply!` only moves forward; a fresh run is the existing combine flow. |
| Per-record atomicity preserved | A create with nested segments is still one `save!` within its chunk. |
| `apply_progress` not reset on failure | Shows true partial progress and supports resume. |
