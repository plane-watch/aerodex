# VRS Route Importer

Imports airline route and route-segment data from the VRS
[`vradarserver/standing-data`](https://github.com/vradarserver/standing-data/tree/main/routes/schema-01)
GitHub repository.

The importer does not import airline or airport data. It resolves each route's
airline and airport codes against the operators and airports already in the
Aerodex database.

## Pipeline

Like the other data sources, routes use a two-stage pipeline.

### Stage 1 — Import (raw data into `route_sources`)

`Processors::Route::VRS` fetches route CSV files from GitHub and upserts the rows
verbatim into the `route_sources` table. Run it from the console:

```ruby
# Import every airline discovered from the GitHub API tree.
Processors::Route::VRS.import_all_from_github

# Import a single airline by its callsign code.
Processors::Route::VRS.import_airline('QFA')

# Import from a local clone of the repository's routes/schema-01 directory.
Processors::Route::VRS.import('/path/to/standing-data/routes/schema-01')
```

### Stage 2 — Combine (source rows into canonical routes)

`Processors::Route::Route#combine_sources` resolves each source row's airline code
to an `Operator` (by ICAO, then IATA) and each airport code to an `Airport`
(by ICAO, then IATA), then stages a `Route` — with its `RouteSegment` children as
nested attributes — into a `StagedBatch` for review.

A route is skipped (and recorded in a `SourceImportReport`) if its operator or any
of its airports cannot be resolved. Skipped routes are retried automatically on the
next combine once the missing operators/airports exist.

Run the combine via the admin Processors page, the rake task, or the console:

```bash
rake processors:run[Route]        # enqueues a background job
rake processors:run_sync[Route]   # runs synchronously
```

```ruby
# Scope a run to a single airline to keep the staged batch reviewable.
Processors::Route::Route.combine_sources(airline_code: 'QFA')
```

## Reviewing batches

An unscoped combine stages one change per route across all airlines, which can
produce a very large, impractical-to-review batch. When changes must be reviewed
manually, run the combine per airline with `airline_code:` so each batch contains
a single operator's routes.
