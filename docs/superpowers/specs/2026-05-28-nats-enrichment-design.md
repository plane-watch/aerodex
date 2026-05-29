# NATS Enrichment Service Design

**Date:** 2026-05-28
**Status:** Approved design, pending implementation plan

## Purpose

Aerodex is the canonical aviation reference database (aircraft, operators,
manufacturers, airports, runways, routes). A separate flight-tracking pipeline
enriches a live stream of ADS-B observations with this reference data.

Today that enrichment is served by a Go microservice (`pw_atc_api` in
`plane-watch/pw-pipeline`) that holds its own copy of the data and answers NATS
RPCs. The goal is to let aerodex — the system of record — answer enrichment
requests directly off the NATS bus, removing the need to replicate aerodex data
into a separate service and removing an HTTP hop.

This design covers a new, aerodex-owned set of NATS subjects under the `v2.*`
namespace. It does **not** replace `pw_atc_api`; the two run side by side, and
how the upstream pipeline migrates between them is out of scope for aerodex.

## Scope

### In scope

Three request-reply subjects, each a single-identifier lookup returning a fully
assembled reference record:

- `v2.enrich.aircraft` — look up an aircraft by ICAO Mode-S hex.
- `v2.enrich.route` — look up a route by callsign.
- `v2.enrich.airport` — look up an airport (with its runways) by ICAO or IATA code.

### Out of scope

- **Feeder management** (`v1.feeder.*` in the Go service). Aerodex does not model
  feeders, users, or muxes, so these stay in `pw_atc_api`.
- **Fuzzy / multi-result search** (e.g. airport name search). A different access
  pattern (Meilisearch-backed, multi-result); noted as a possible future
  `v2.search.*` subject, not built here.
- **Write operations.** This service is read-only.
- **Caching inside aerodex.** The upstream enriching service already caches, so
  aerodex sees only miss traffic. Per YAGNI, no cache is built now. The component
  boundaries (below) leave a clean seam to add one later if a load test shows DB
  pressure.

## Constraints and context

- **Throughput:** the raw ADS-B stream is 1,000–10,000 req/s, but the upstream
  service caches, so aerodex sees only cache-miss traffic (new/unseen airframes
  and callsigns). The effective sustained rate against aerodex is expected to be
  far lower. This is an assumption to validate with a load test before scaling.
- **Rails 8.1.2, Ruby 3.3.7, PostgreSQL, Meilisearch.** Single Puma process today;
  no existing NATS, background-job, or message-bus infrastructure.
- **Prometheus** is already run in this environment; metrics are expected.

## Wire contract (v2)

Clean, idiomatic JSON: `snake_case` keys, nested objects for associations, and an
explicit `found` boolean so a miss is unambiguous (the Go service returned a
shaped-empty object on a miss, which conflated "not found" with "found but
empty"). Source/provenance metadata, counter-cache columns, internal IDs, and
timestamps are deliberately excluded from the default response.

### Request envelope

Each request is a small JSON object rather than a raw string. This costs almost
nothing and lets the response stay lean by default while allowing opt-in
expansion via an `include` array.

```jsonc
// v2.enrich.aircraft
{ "icao": "7C1469", "include": ["provenance"] }   // include is optional

// v2.enrich.route
{ "callsign": "QFA123" }

// v2.enrich.airport — accepts either icao or iata
{ "icao": "YPPH" }
{ "iata": "PER" }
```

### Shared embedded objects

**`country`** — used wherever a country is referenced. Drawn from the structured
`Country` association (the denormalised free-text `country` string columns on
`operators`/`airports` are ignored).

```json
{
  "name": "Australia",
  "iso_2char_code": "AU",
  "iso_3char_code": "AUS",
  "iso_num_code": "036",
  "capital": "Canberra"
}
```

**`manufacturer`** — full non-metadata coverage.

```json
{
  "name": "Boeing",
  "icao_code": "BOEING",
  "alt_names": ["Boeing Commercial Airplanes"],
  "country": { "...": "country object, may be null" }
}
```

**`operator`** — full coverage including a shallow `parent` for multi-unit
organisations (e.g. RAF, CAA). The parent is shallow (no nested parent-of-parent,
no country) to bound response size.

```json
{
  "name": "Qantas",
  "icao_code": "QFA",
  "iata_code": "QF",
  "country": { "...": "country object, may be null" },
  "parent": { "name": "Qantas Group", "icao_code": null, "iata_code": null }
}
```

`parent` is `null` when the operator is standalone or is itself a parent.

**`aircraft_type`**

```json
{
  "type_code": "B738",
  "name": "737-800",
  "full_name": "Boeing 737-800",
  "category": "airplane",
  "wtc": "M",
  "engines": 2,
  "engine_type": "jet",
  "manufacturer": { "...": "manufacturer object, may be null" }
}
```

`full_name` uses the existing `AircraftType#full_name` (manufacturer name +
type name). `category` is the enum label string.

**`runway`** — canonical `airport_runways` columns. `heading`, `length`, and
`width` are unit-less decimals as stored (the source units are not recorded in
the canonical table).

```json
{
  "name": "03/21",
  "le_ident": "03",
  "he_ident": "21",
  "heading": 30.0,
  "length": 3444.0,
  "width": 45.0,
  "surface": "asphalt",
  "lighted": true,
  "closed": false
}
```

**`airport_summary`** — used inside route segments. No runways, to keep route
responses lean; full runways are available via `v2.enrich.airport`.

```json
{
  "icao_code": "YSSY",
  "iata_code": "SYD",
  "name": "Sydney Kingsford Smith",
  "city": "Sydney",
  "latitude": -33.946,
  "longitude": 151.177,
  "altitude": 21.0,
  "timezone": "Australia/Sydney",
  "country": { "...": "country object, may be null" }
}
```

### Responses

**`v2.enrich.aircraft`**

```json
{
  "found": true,
  "aircraft": {
    "icao": "7c1469",
    "registration": "VH-VZX",
    "serial_number": "44567",
    "manufacture_year": 2015,
    "registration_date": "2015-03-12",
    "owner": "Qantas Airways Ltd",
    "status": "active",
    "model": "737-838",
    "name": "Boomerang",
    "engine_count": 2,
    "engine_model": "CFM56-7B",
    "cabin_configuration": "J12Y162",
    "type": { "...": "aircraft_type object, may be null" },
    "operator": { "...": "operator object, may be null" },
    "registration_country": { "...": "country object" }
  }
}
```

`name` is the aircraft's `aircraft_name` column. `status` is the enum label.

**`v2.enrich.route`** — segments carry full `airport_summary` objects and the
scheduled times from `route_segments`, ordered by `order`.

```json
{
  "found": true,
  "route": {
    "callsign": "QFA123",
    "operator": { "...": "operator object" },
    "segments": [
      { "order": 0, "departing_time": "09:30:00", "arrival_time": null,       "airport": { "...": "airport_summary" } },
      { "order": 1, "departing_time": null,       "arrival_time": "13:05:00", "airport": { "...": "airport_summary" } }
    ]
  }
}
```

**`v2.enrich.airport`** — full airport with runways and flight information region.

```json
{
  "found": true,
  "airport": {
    "icao_code": "YPPH",
    "iata_code": "PER",
    "wmo_code": "94610",
    "name": "Perth International Airport",
    "city": "Perth",
    "latitude": -31.940278,
    "longitude": 115.966944,
    "altitude": 67.0,
    "timezone": "Australia/Perth",
    "country": { "...": "country object" },
    "flight_information_region": { "icao_code": "YMMM", "region": "Melbourne" },
    "runways": [ { "...": "runway object" } ]
  }
}
```

`flight_information_region` is `null` when the airport has none.

### Misses and the optional provenance block

A miss on any subject returns `{ "found": false }`.

When the request includes `"include": ["provenance"]`, a `provenance` block is
added to the response covering the primary entity's own fields (not nested
associations). It is built from the existing `HasFieldProvenance` concern
(`field_provenance` column / `provenance_for`). Shape:

```json
{
  "found": true,
  "aircraft": { "...": "as above" },
  "provenance": {
    "registration": { "source": "casa", "trust": 90 },
    "owner": { "source": "casa", "trust": 90 }
  }
}
```

The exact per-field shape mirrors what `provenance_for` already returns.

## Error and miss conventions

The service **always sends a reply** (the Go airport handler failed to reply on a
DB error, causing the caller to time out — a bug not to repeat).

| Situation | Reply |
|---|---|
| Lookup miss | `{ "found": false }` |
| Malformed request (bad JSON, missing/empty key) | `{ "error": "...", "code": "bad_request" }` |
| Unexpected internal error | logged; `{ "error": "internal", "code": "internal" }` |

## Architecture

A dedicated, long-lived consumer process — separate from Puma — connects to NATS
and answers requests. It is **never** started from a Rails initializer or inside
the web process.

### Process model

- A new executable, `bin/enrichment-server`, boots the eager-loaded Rails
  environment and runs the NATS server loop.
- Declared as its own process type (Docker `command:` / Kamal role / Procfile
  line), scaled by running N replicas.
- Configuration via environment variables:
  - `NATS_URL` (and optional credentials/TLS settings)
  - `NATS_QUEUE_GROUP` (default `aerodex-enrich-v2`)
  - `NATS_CONCURRENCY` (callback concurrency; default modest, e.g. 8)
  - `METRICS_PORT` (Prometheus exporter)

### Components

Under `app/services/enrichment/`, matching the existing service-object
convention. Each has one job and is testable in isolation.

- **`Enrichment::NatsServer`** — connection lifecycle only: read config, connect,
  register subscriptions, trap `SIGTERM`/`SIGINT` → `drain`, join. Knows nothing
  about aviation domain models.
- **Subject registry / dispatcher** — maps an exact subject string to its handler;
  keeps the server generic.
- **`Enrichment::AircraftHandler`, `RouteHandler`, `AirportHandler`** — per
  subject: parse the request envelope, invoke the query, serialise, `respond`.
  The handler body is wrapped in `Rails.application.executor.wrap` (ActiveRecord
  connection checkout/return, reloader safety) and instrumented for metrics in one
  place.
- **`Enrichment::AircraftQuery`, `RouteQuery`, `AirportQuery`** — encapsulate DB
  access with correct eager loading (`includes`) to avoid N+1s. Reuse existing
  ActiveRecord models.
- **`Enrichment::AircraftSerializer`, `RouteSerializer`, `AirportSerializer`**,
  plus shared serializers for the embedded `country`, `operator`, `manufacturer`,
  `aircraft_type`, `runway`, and `airport_summary` objects — model → v2 hash,
  including the opt-in provenance block.

### Data flow

```
NATS msg (v2.enrich.*)
  → NatsServer (callback thread pool)
    → executor.wrap + metrics instrumentation
      → Handler (parse envelope)
        → Query (indexed ActiveRecord lookup + includes)
          → Serializer (model → v2 hash)
            → JSON → msg.respond(reply_inbox)
```

## Concurrency and the database pool

Handlers run on `nats-pure`'s callback thread pool. The non-negotiable
correctness rule: the runner process's ActiveRecord pool size must be **≥ the
callback concurrency**, and every handler must wrap its body in the Rails
executor so connections are returned to the pool. Mismatched sizing causes
`ConnectionTimeoutError` under load.

CPU parallelism within one process is limited by MRI's GIL, but these handlers
are I/O-bound (one indexed query each), so the thread pool gives useful
concurrency. Horizontal scaling is achieved by running more replicas in the same
NATS queue group — the queue group load-balances requests across all replicas
(and is also how this coexists with any other subscribers).

## Observability

- **Structured logging** per request: subject, lookup key, `found?`, latency.
- **Prometheus metrics** via the `prometheus-client` gem, exposed on a lightweight
  HTTP listener on `METRICS_PORT` (mirroring how `pw_atc_api` exposed its metrics
  port), scraped per replica:
  - `aerodex_enrichment_requests_total{subject, result}` — counter;
    `result` ∈ `hit` / `miss` / `bad_request` / `error`.
  - `aerodex_enrichment_request_duration_seconds{subject}` — histogram.
  - `aerodex_enrichment_nats_reconnects_total` — counter (reconnect storms).
  - `aerodex_enrichment_in_flight{subject}` — gauge.

Because each runner is a single OS process (concurrency is in-thread), a single
Prometheus registry suffices — no multiprocess-mode complications.

## Graceful shutdown

On `SIGTERM`/`SIGINT`, call `nc.drain` (not `close`): stop accepting new
messages, let in-flight handlers finish and emit their replies, flush, then exit.
The orchestrator's termination grace period must exceed the NATS drain timeout
(default 30s) to avoid a `SIGKILL` mid-drain.

## Testing strategy (TDD)

- **Query objects** against the DB (fixtures/factories), including miss cases.
- **Serializers** — model → expected hash, with and without the provenance block,
  including null associations (e.g. aircraft with no operator).
- **Handlers** — feed a stubbed message object, assert the captured `respond`
  payload. No network, so the suite stays fast and deterministic.
- **One integration test** against a real `nats-server` to prove end-to-end wiring
  (subscribe → request → reply).

## Dependencies to add

- `nats-pure` (~> 2.5) — official threaded Ruby NATS client.
- `prometheus-client` — metrics.

## Key decisions and rationale

| Decision | Rationale |
|---|---|
| New `v2.*` subjects, not replacing `pw_atc_api` | Aerodex needn't care about cutover; clean idiomatic contract; no feeder data to model. |
| `snake_case` JSON with explicit `found` flag | Idiomatic; removes the Go service's miss/empty ambiguity. |
| JSON request envelope (not raw string) | Cheap; enables opt-in `include` without bloating the default response. |
| Dedicated `bin/enrichment-server` process | A long-lived consumer must not live in Puma or an initializer. |
| No caching in aerodex (yet) | Upstream already caches; aerodex sees only misses. YAGNI; seam left for later. |
| Scale via queue-group replicas | Works around MRI's GIL for throughput. |
| Structured `Country` association over free-text column | Single source of truth; richer data. |
| Runways only via `v2.enrich.airport` | Keeps route responses lean. |
