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
| `RAILS_MASTER_KEY` | (required)           | Decrypts the credentials at boot.        |

`RAILS_MASTER_KEY` is required even though the service serves no sessions: it
boots the full Rails environment, and Devise's `devise.secret_key` initialiser
resolves `secret_key_base` from the encrypted credentials during boot.

These variables are read with `ENV.fetch(name, default)`, so a variable set to an
empty string is not the same as an unset one. An empty `METRICS_PORT` binds an
arbitrary port rather than 9602, and an empty `NATS_QUEUE_GROUP` is not the
default group.

Scale by running more replicas: every replica joins the same queue group, so NATS
load-balances requests across them.

### Under Docker Compose

The production stack (`compose.yaml`) runs the consumer as the `enrich` service.
It uses the same image as `web` with the command overridden to
`./bin/enrichment-server`, so no separate build is needed. Scale it with
`docker compose up --scale enrich=N`.

The broker is external — it is shared with the flight-tracking pipeline — so the
stack does not run one and `NATS_URL` must be supplied:

```bash
NATS_URL=nats://user:pass@broker:4222 docker compose up -d
```

Because `NATS_URL` is declared as a required variable, it must be present for
every `docker compose` invocation against `compose.yaml` — including `down` and
`ps`. Keep the four required secrets in a `.env` file, which Compose reads
automatically and which is ignored by both git and Docker.

Two settings on that service are load-bearing:

- `SKIP_MIGRATIONS: "true"` — the shared entrypoint runs `db:prepare` on every
  container start, and the `web` service owns migrations. The consumer skips
  them and waits on `web` becoming healthy first. The ordering holds because the
  entrypoint runs `db:prepare` before it execs Puma, so a web server answering
  `/up` has necessarily finished migrating; `/up` itself only reports that the
  application booted, not that the schema is current.
- `stop_grace_period: 45s` — longer than the drain wait, so the consumer
  finishes flushing in-flight replies before Docker escalates to `SIGKILL`.

Without that ordering the consumer would still start, connect and report
healthy, then answer every request with `{"error": "internal"}` until migrations
landed, because the handlers rescue internally.

The development stack (`compose.dev.yaml`) runs a `nats` broker container and
starts the consumer inside the `web` container, as the `enrich` entry in
`Procfile.dev` — one container runs the entrypoint's first-run seeding, so a
second Rails service would race it. The broker's monitoring endpoint is
published on `127.0.0.1:8222`, where `/subsz?subs=1` confirms the consumer has
subscribed to `v2.enrich.*` under its queue group. The consumer's metrics are
published on `127.0.0.1:9602`.

## Subjects and contract

All requests are a small JSON object; all responses are JSON with `snake_case`
keys and an explicit `found` boolean. A miss returns `{ "found": false }`.

### `v2.enrich.aircraft`

Request: `{ "icao": "7C1469", "include": ["provenance"] }` (`include` optional).

Returns the aircraft with nested `type`, `operator` and `registration_country`.
With `"include": ["provenance"]`, a top-level `provenance` block reports the
source and confidence for each tracked field.

### `v2.enrich.routes`

Request: `{ "callsign": "QFA123" }`.

Returns the route with its `operator` and ordered `segments`; each segment embeds
a lean airport summary (no runways) and the scheduled times.

### `v2.enrich.airports`

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

Prometheus metrics are exposed on `METRICS_PORT` at `/metrics`. Under Compose the
endpoint is reachable on the stack's network at `enrich:9602/metrics`; it is not
published to the host, since it carries no authentication. The metrics server is
started only after the NATS connection and subscription are established, so a
`200` from it also indicates the consumer is connected to the broker — the
`enrich` service uses it as its healthcheck.

The metrics are:

- `aerodex_enrichment_requests_total{subject, result}` — `result` is `hit`,
  `miss`, `bad_request` or `error`.
- `aerodex_enrichment_request_duration_seconds{subject}` — handler latency.
- `aerodex_enrichment_nats_reconnects_total` — NATS reconnects.
- `aerodex_enrichment_in_flight{subject}` — requests currently being processed.

## Shutdown

On `SIGTERM`/`SIGINT` the process drains the NATS subscription: it stops
accepting new messages, lets in-flight requests finish and flushes their replies,
then exits. The drain runs on a background thread inside the NATS client, so
shutdown waits on the connection's close callback for up to
`NatsServer::DRAIN_WAIT_SECONDS` (35s, slightly longer than the client's own 30s
drain timeout) before giving up and exiting anyway. Give the orchestrator a
termination grace period longer than that; `compose.yaml` uses 45s.

The signal traps are installed once the service is connected and subscribed, so
a signal received during Rails boot exits immediately under Ruby's default
handler.

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
