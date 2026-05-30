# VRS GitHub Route Importer — Design

- **Date:** 2026-05-30
- **Status:** Approved design, ready for implementation planning
- **Branch:** `feature/vrs-github-route-importer`

## Summary

Import airline route and route-segment data from the VRS (Virtual Radar Server)
`vradarserver/standing-data` GitHub repository into Aerodex. The repository
publishes routes as CSV files under `routes/schema-01/`, organised alphabetically
by airline callsign code.

This adds a new data source for the existing (but currently unpopulated) `Route`
and `RouteSegment` models. It follows the established two-stage processor
architecture: a raw import into a source table, followed by a combine into
canonical records via the staged-batch review system.

Crucially, the importer does **not** import airline or airport data from the VRS
repository. Aerodex already holds operator and airport data. The combine step
resolves the route's airline and airport codes against our **own** database to
populate the required foreign keys.

## Background

### Source data format

The VRS `routes/schema-01` directory contains:

- 26 letter-named folders (`A`–`Z`), grouping routes by the first character of
  the airline callsign code.
- Per-airline CSV files: `<CODE>-all.csv` for airlines with ≤10,000 routes, or
  `<CODE>-<digit>.csv` split files for larger airlines.

Each route CSV has five columns:

| Column | Description |
|---|---|
| `Callsign` | The normalised callsign, e.g. `QFA1`. |
| `Code` | The code portion of the callsign, e.g. `QFA`. |
| `Number` | The number portion of the callsign, e.g. `1`. |
| `AirlineCode` | The code used to look up the owning airline, e.g. `QFA`. |
| `AirportCodes` | Hyphen-separated airport codes in flight order, e.g. `YSSY-WSSS-EGLL`. |

Airport codes are the VRS airport "Code" field — the ICAO code (4 characters)
where known, falling back to the IATA code (3 characters). `AirlineCode` is the
VRS airline "Code" field — likewise ICAO-preferred with IATA fallback.

Example (`Q/QFA-all.csv`):

```
Callsign,Code,Number,AirlineCode,AirportCodes
QFA1,QFA,1,QFA,YSSY-WSSS-EGLL
QFA10,QFA,10,QFA,EGLL-YPPH
QFA100,QFA,100,QFA,KLAX-YMML
```

### Existing architecture

Aerodex processors follow a consistent two-stage pattern:

1. **Import processors** (e.g. `Processors::Aircraft::VRS::StandingData`,
   `Processors::Operator::VRSData`) fetch raw external data and upsert it
   verbatim into single-table-inheritance `*_sources` tables. Raw data needs no
   review, so these do not use the staged-batch system. They are invoked from the
   console or a dedicated method.
2. **Combine processors** — the canonical `Processors::<Entity>::<Entity>` class,
   exposing `combine_sources(triggered_by:)` — turn source rows into canonical
   models. They stage every create/update as a `StagedChange` within a
   `StagedBatch` for human review and approval before the changes are applied.
   `ProcessorJob`, the `processors:run` rake tasks, and the admin UI all invoke
   combine processors via the `Processors::<Entity>::<Entity>` naming convention.

The `Route` and `RouteSegment` models already exist but have no source model,
processor, or combine. This design is a greenfield build following the patterns
above.

The relevant canonical schema:

- `Route`: `operator_id` (required), `call_sign`, `route_segments_count`
  (counter cache).
- `RouteSegment`: `route_id` (required), `airport_id` (required association),
  `order`, `arrival_time`, `departing_time`.

## Goals

- Import VRS route data from GitHub into a new `route_sources` table.
- Combine source rows into canonical `Route` + ordered `RouteSegment` records,
  resolving operator and airport foreign keys against the existing Aerodex
  database.
- Integrate with the existing staged-batch review flow.
- Guarantee that every persisted route is complete and valid.

## Non-goals

- Importing airline or airport data from the VRS repository. Operators and
  airports are resolved against existing Aerodex records only.
- Populating segment arrival/departure times. VRS route data carries no times;
  `arrival_time` and `departing_time` remain nil.
- Extending the core `StagedBatch`/`StagedChange` system. The parent-child
  relationship is handled within the route combine via nested attributes.

## Design

### Stage 1 — Import processor: `Processors::Route::VRS`

File: `app/models/processors/route/vrs.rb`, class `Processors::Route::VRS`.

The naming follows the simpler operator precedent
(`Processors::Operator::VRSData`) rather than the aircraft layout
(`Aircraft::VRS::StandingData`). The aircraft `VRS::` module level exists only to
group multiple VRS-sourced processors under one entity (the aircraft list and
aircraft-type model types). Routes have exactly one VRS dataset, so no module
grouping is needed.

Responsibilities, mirroring `Processors::Aircraft::VRS::StandingData`:

- Discover CSV files via the GitHub API tree, matching the path patterns
  `routes/schema-01/<LETTER>/<CODE>-all.csv` and
  `routes/schema-01/<LETTER>/<CODE>-<digit>.csv`.
- Provide:
  - `import(directory_path)` — import from a local clone of the repository.
  - `import_all_from_github(progress: true)` — discover and import every route
    file from GitHub.
  - `import_airline(code)` — import a single airline's file(s); useful for
    testing and for feeding airline-scoped combine runs.
- Parse the CSV (`Callsign,Code,Number,AirlineCode,AirportCodes`), handling the
  UTF-8 BOM as the aircraft importer does.
- Upsert rows into `Source::Route::VRSRouteSource` keyed on `(callsign, type)`.
  `Code` and `Number` are stored in the `data` JSONB column rather than dedicated
  columns, keeping the table lean while preserving the raw values.

The processor extends `Processors::Base` directly; it needs none of the
route-combine helpers.

### Stage 2 — Combine processor: `Processors::Route::Route`

File: `app/models/processors/route/route.rb`, class `Processors::Route::Route`,
extending `Processors::Base`. Exposes:

```ruby
combine_sources(triggered_by: nil, airline_code: nil)
```

The optional `airline_code` argument scopes a run to a single operator's routes.
This keeps a staged batch to a reviewable size (a few thousand routes at most)
and is the recommended way to run the combine when changes must be reviewed
manually. See "Known tradeoffs".

**Algorithm.** Within a `with_staged_batch(entity_type: "Route", ...)` block,
preload reference data into memory, then iterate over the includable
`route_sources` (optionally filtered by `airline_code`):

1. **Resolve the operator** from `airline_code` using preloaded `Operator`
   indexes — by `icao_code` first, then `iata_code`. If unresolved, skip the
   route and record an entry in the import report. (`Route.operator` is
   required.)
2. **Resolve the airports** — split `airport_codes` on `-` and look each code up
   in preloaded `Airport` indexes (`by_icao` then `by_iata`; the 4-vs-3-character
   namespaces do not meaningfully collide). If **any** code fails to resolve,
   skip the **whole** route and record it in the import report. This guarantees
   every persisted route is complete.
3. **Determine identity and operation** using a preloaded index of existing
   routes keyed on `(operator_id, call_sign)` (where `call_sign` is the source
   `callsign`, e.g. `QFA1`):
   - No existing route → stage a **create**.
   - Existing route whose ordered segment `airport_id` sequence matches the
     resolved sequence → **unchanged** (update the summary only, stage nothing).
   - Existing route whose segments differ → stage an **update** that replaces the
     segments.

Routes hold no references to one another, and each source row produces exactly
one route with a unique callsign. Unlike the operator combine, no intra-batch
staged-record cache is required.

**Reference resolution failures** are collected and written to the batch notes /
`SourceImportReport`, consistent with how other processors report errors. Because
the combine re-reads `route_sources` on each run, routes skipped due to a missing
operator or airport are retried automatically on the next combine once the
underlying Aerodex data catches up.

### Staging parent + child (Approach A: aggregate via nested attributes)

The generic apply path in `StagedBatch#apply_single_change` applies each
`StagedChange` independently:

```ruby
record = model_class.new(change.new_values)  # create
record.save!
```

A `RouteSegment`'s `route_id` does not exist until its parent `Route` is actually
applied (not merely staged), so staging segments as separate `StagedChange`
records would produce orphans on apply. To avoid changing the shared staged-batch
core, the route combine stages **one `StagedChange` per route**, carrying the
segment data as Rails nested attributes:

- **Create** diff:

  ```ruby
  {
    "operator_id"              => [nil, operator_id],
    "call_sign"                => [nil, callsign],
    "route_segments_attributes" => [nil, [{ "airport_id" => …, "order" => 0 }, …]]
  }
  ```

- **Update** diff (wholesale segment replacement):

  ```ruby
  {
    "route_segments_attributes" => [
      <existing segments summary>,
      [{ "id" => existing_id, "_destroy" => true }, …] +
        [{ "airport_id" => …, "order" => 0 }, …]
    ]
  }
  ```

On apply, `new_values = diff.transform_values(&:last)`, and
`Route.new(new_values).save!` / `Route.find(id).update!(new_values)` cascades
through nested attributes — creating or replacing all segments atomically with
the route. The counter cache (`route_segments_count`) and the post-apply
Meilisearch reindex both work through the normal ActiveRecord path.

Because the generic `stage_change` builds diffs from flat `record.attributes`,
the combine uses a small custom `stage_route` method to emit the nested-attribute
diff. This is the only deviation from the standard staging helper and is local to
the route combine.

### Database changes

**New table `route_sources`** (single-table inheritance, mirroring other
`*_sources` tables):

| Column | Type | Notes |
|---|---|---|
| `type` | string, not null | STI discriminator. |
| `callsign` | string, not null | Full normalised callsign; natural key. |
| `airline_code` | string, not null | Raw `AirlineCode`; resolves the operator. |
| `airport_codes` | string, not null | Raw hyphen-separated airport codes. |
| `import_date` | datetime, not null | |
| `data` | jsonb, default `{}`, not null | Stores `Code`, `Number`, and any extras. |
| `excluded` | boolean, default false, not null | From `HasSourceExclusion`. |
| `exclusion_reason` | string | From `HasSourceExclusion`. |
| `excluded_at` | datetime | From `HasSourceExclusion`. |
| `excluded_by` | string | From `HasSourceExclusion`. |

Indexes: unique `(callsign, type)` (upsert natural key), `airline_code`,
`excluded`, `data`.

**`routes` table:** add a unique index on `(operator_id, call_sign)`, giving
routes a natural identity for idempotent re-runs. No such index exists today.

### Source models

- `Source::Route::RouteSource` — abstract base. Sets
  `self.table_name = 'route_sources'`, includes `HasSourceExclusion`, validates
  presence of `callsign`, `airline_code`, `airport_codes`, and `import_date`, and
  provides an `airport_code_list` helper (`airport_codes.split('-')`).
- `Source::Route::VRSRouteSource < RouteSource` — STI subclass, parallel to
  `Source::Aircraft::VRSAircraftSource`.

### Model changes — `Route`

- `accepts_nested_attributes_for :route_segments, allow_destroy: true` — enables
  the Approach A apply path.
- `validates :call_sign, uniqueness: { scope: :operator_id }` — matches the new
  unique index.
- `has_many :route_segments, dependent: :destroy` — the model currently declares
  no `dependent:` option; adding `:destroy` ensures deleting a route cleans up its
  segments. This is a targeted fix in support of the new combine, not unrelated
  refactoring.

`RouteSegment` requires no changes. Its `arrival_time` and `departing_time`
remain nil because VRS route data carries no times.

### Registration

Add `'Route'` to `Admin::ProcessorsController::PROCESSOR_ENTITY_TYPES`. This
surfaces the combine in the admin UI and enables `rake processors:run[Route]` and
`rake processors:run_sync[Route]` via the existing naming convention. The Stage 1
import processor is invoked from the console or its own method, consistent with
the other raw VRS importers (which have no rake wiring).

## Testing

- **Import processor** (`Processors::Route::VRS`): Excon-mocked CSV fetch →
  `route_sources` upsert; UTF-8 BOM handling; idempotency on re-import (upsert by
  `(callsign, type)`); `Code`/`Number` captured in `data`.
- **Combine processor** (`Processors::Route::Route`): with operator and airport
  fixtures —
  - resolves operator + airports and stages a create with correctly-ordered
    segments;
  - skips the route and logs when the operator is unresolved;
  - skips the whole route and logs when any airport is unresolved;
  - detects an unchanged route (matching segment sequence) and stages nothing;
  - stages a segment-replacing update when segments differ;
  - applying the batch produces a `Route` with `RouteSegment` records in the
    correct order.
- **`Route` model**: `call_sign` uniqueness scoped to `operator_id`; nested
  attributes create and replace segments correctly on apply.

## Documentation

- Update `README.md`'s data-source/processor listing to include routes.
- Add a `doc/` page describing the two-stage route import flow, console usage for
  `Processors::Route::VRS`, the combine, and airline-scoped combine runs for
  manageable review batches.

## Known tradeoffs

- **Batch size.** A full, unscoped combine stages one `StagedChange` per route —
  on the order of 100,000+ rows across all airlines in a single batch. This was
  an explicit decision to keep routes consistent with the existing per-record
  staging pattern, but such a batch is impractical to review manually. The
  `airline_code:` argument is the escape hatch: running the combine per airline
  yields reviewable batches. This will be documented as the recommended approach
  when manual review is required.
- **Airport code ambiguity.** Resolution relies on the VRS airport "Code"
  matching an Aerodex `icao_code` or `iata_code`. Routes referencing airports
  absent from our database are skipped (by design) and retried on subsequent
  combine runs as our airport coverage grows.
