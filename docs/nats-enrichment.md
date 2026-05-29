# NATS Enrichment Service

Aerodex serves its aviation reference data over NATS so the flight-tracking
pipeline can enrich a live ADS-B stream without replicating aerodex's database.
The service is a dedicated, long-lived consumer process — separate from the Puma
web server — that answers NATS request-reply RPCs.

It exposes a new, aerodex-owned `v2.enrich.*` subject set. It does not replace the
existing Go `pw_atc_api` service; the two run side by side.

## Running

```bash
NATS_URL=nats://user:pass@host:4222 bin/enrichment-server
```

Configuration (environment variables):

| Variable           | Default              | Purpose                                  |
|--------------------|----------------------|------------------------------------------|
| `NATS_URL`         | (required)           | NATS server URL.                         |
| `NATS_QUEUE_GROUP` | `aerodex-enrich-v2`  | Queue group; replicas share it.          |
| `METRICS_PORT`     | `9602`               | Prometheus `/metrics` HTTP port.         |

Scale by running more replicas: every replica joins the same queue group, so NATS
load-balances requests across them.

## Subjects and contract

All requests are a small JSON object; all responses are JSON with `snake_case`
keys and an explicit `found` boolean. A miss returns `{ "found": false }`.

### `v2.enrich.aircraft`

Request: `{ "icao": "7C1469", "include": ["provenance"] }` (`include` optional).

Returns the aircraft with nested `type`, `operator` and `registration_country`.
With `"include": ["provenance"]`, a top-level `provenance` block reports the
source and confidence for each tracked field.

### `v2.enrich.route`

Request: `{ "callsign": "QFA123" }`.

Returns the route with its `operator` and ordered `segments`; each segment embeds
a lean airport summary (no runways) and the scheduled times.

### `v2.enrich.airport`

Request: `{ "icao": "YPPH" }` or `{ "iata": "PER" }` (ICAO takes precedence).

Returns the airport with its `country`, `flight_information_region` and full
`runways`. Supports the `provenance` include.

### Errors

| Situation                         | Reply                                            |
|-----------------------------------|--------------------------------------------------|
| Miss                              | `{ "found": false }`                             |
| Malformed request / missing key   | `{ "error": "...", "code": "bad_request" }`      |
| Unexpected internal error         | `{ "error": "internal", "code": "internal" }`    |

The service always replies; it never lets a caller time out on an internal error.

## Metrics

Prometheus metrics are exposed on `METRICS_PORT` at `/metrics`:

- `aerodex_enrichment_requests_total{subject, result}` — `result` is `hit`,
  `miss`, `bad_request` or `error`.
- `aerodex_enrichment_request_duration_seconds{subject}` — handler latency.
- `aerodex_enrichment_nats_reconnects_total` — NATS reconnects.
- `aerodex_enrichment_in_flight{subject}` — requests currently being processed.

## Shutdown

On `SIGTERM`/`SIGINT` the process drains the NATS subscription: it stops
accepting new messages, lets in-flight requests finish and flushes their replies,
then exits. Give the orchestrator a termination grace period longer than the NATS
drain timeout (30s default).

## Testing

The unit and component tests run with the default suite (`./bin/rails test`); they
exercise the queries, serializers, handlers, dispatcher and metrics without a
broker.

An end-to-end round-trip test against a real broker lives at
`test/integration/enrichment/nats_round_trip_test.rb`. It is skipped unless
`NATS_TEST_URL` is set:

```bash
docker run -d -p 4222:4222 nats           # or: nats-server
NATS_TEST_URL=nats://127.0.0.1:4222 bin/rails test test/integration/enrichment/nats_round_trip_test.rb
```

## Design

See `docs/superpowers/specs/2026-05-28-nats-enrichment-design.md` for the full
design rationale.
