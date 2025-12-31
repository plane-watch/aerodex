# Aerodex – Project Specification
*v0.7 — 2024-12-28 (Australia/Perth)*

---

## 1 Purpose & Scope

Aerodex is a **Ruby on Rails** monolith that provides a **free, open registry of aviation metadata** for:

* **Plane-Watch** (`https://app.plane.watch`) — interactive flight-tracking UI.
* **Third-party consumers** via a versioned JSON/REST API.

The app:

1. **Ingests** data from heterogeneous public sources (CSV, JSON, XML, HTML scrapes, REST APIs).
2. **Normalises & deduplicates** feeds into a **canonical domain model** (Aircraft, Operator, Route, …).
3. **Serves** the consolidated data through:
   * A **Hotwire/Tailwind** web UI.
   * A **northbound REST API** (`/api/v1`).
4. **Audits & traces** every field back to its upstream source.

---

## 2 Architecture Overview

```text
Web UI (Hotwire/Turbo) ──► Northbound API (REST/JSON) ──► Domain Models (PostgreSQL)
                                      ▲                         │
                                      │                         ▼
                             Processor Framework (ETL) ◄── Sidekiq Jobs
                                      │
                             External Data Sources
```

| Layer | Duties | Tech / Gems |
|-------|--------|------------|
| **UI** | Browsing, search, admin dashboards | Hotwire, ViewComponent, Tailwind CSS |
| **API** | Versioned JSON, pagination, filtering | Rails controllers, `pagy`, `active_model_serializers` |
| **Domain Models** | Canonical entities, validations, audit | ActiveRecord, PaperTrail, Meilisearch |
| **Processors** | Fetch → parse → merge → report | POROs in `app/models/processors/`, `http`, `csv`, `nokogiri` |
| **Jobs** | Schedule and execute imports | Sidekiq + Sidekiq-Cron |
| **Storage** | Primary data, search, file blobs | PostgreSQL, Meilisearch, S3/MinIO |

---

## 3 Canonical Domain Model (abridged)

The fields listed below are preliminary, they may change as the project evolves.

| Model | Key Attributes | Notes |
|-------|----------------|-------|
| **Aircraft** | `icao` (mode-S), `registration`, `serial_number`, `aircraft_type_id`, `operator_id`, `status` (enum) | Indexed on `icao`, `registration` |
| **AircraftType** | `name`, `type_code` (ICAO), `category` (enum), `manufacturer_id` | |
| **Manufacturer** | `name`, `icao_code`, `country_id`, `alt_names` (jsonb) | |
| **Operator** | `name`, `icao_code`, `iata_code`, `country_id` | |
| **Airport** | `iata_code`, `icao_code`, `latitude`, `longitude`, `country_id` | |
| **Route** | `operator_id`, `call_sign`; has many **RouteSegments** | |
| **RouteSegment** | `route_id`, `airport_id`, `sequence`, `sta`, `std` | |
| **Country** | ISO-3166 codes, `name`, `capital` | |
| **Source** | `type`, `imported_at`, `data` (jsonb raw blob) | One row per upstream record |
| **SourceImportReport** | `importer_type`, `processed_count`, `error_count`, `details` (jsonb) | Summarises each ETL run |
| **SourceTrustScore** | `entity_type`, `source_type`, `field_name`, `base_trust` | Configurable trust scores per source/field |
| **UserContribution** | `user_id`, `entity_type`, `entity_id`, `field_name`, `old_value`, `new_value`, `status` | User-submitted corrections |

All canonical tables include:
- `created_at`, `updated_at` — standard timestamps
- `field_provenance` (jsonb) — per-field source attribution (see §4.3)
- `last_combined_at` — timestamp of last combine operation

All canonical tables are versioned via **PaperTrail**.

---

## 4 Processor Framework

**Location:** `app/models/processors/`

Processors use a two-tier pattern with class methods:

```ruby
class Processors::Base
  BATCH_SIZE = 1000

  class << self
    def get_source_from_url(url)         # HTTP fetching with mock support
    def with_bulk_import(&block)         # Disables versioning/indexing during bulk ops
    def batch_upsert(records, model:, unique_by:, batch_size: BATCH_SIZE)
    def new_import_report(errors, count) # Creates SourceImportReport
    def silence_active_record            # Suppresses SQL logging
  end
end

# Source importers: import external data into source tables
Processors::Aircraft::CASA::CSV.import_from_file(path)
Processors::Operator::VRSData.import_from_github

# Combine processors: merge sources into canonical records
Processors::Operator::Operator.combine_sources
Processors::Airport::Airport.combine_sources
```

See `docs/data-pipeline.md` for comprehensive documentation on the processor architecture.

### 4.1 Workflow

The key data pipeline workflow is described below. The key aim is to be liberal about the data we ingest but strict about what we insert and combine.

1. **Fetch** — stream remote file or API.
2. **Parse** — convert to enumerable of hashes.
3. **Upsert Source** — `*_sources` table (`UPSERT` by primary key).
4. **Combine** — deterministic priority rules, fuzzy matching helpers (Trigram similarity).
5. **Report** — create `SourceImportReport` with metrics & errors.

**Sidekiq** workers execute imports; long jobs split by source to keep queue latency low.

### 4.2 Guidelines

| Concern | Guideline |
|---------|-----------|
| **Scalability** | Stream files >50 MB, use `COPY` for bulk inserts. |
| **Idempotency** | Importers re-runnable without side-effects (UPSERT only). |
| **Traceability** | Persist original row JSON, reference canonical via FK. |
| **Naming** | Adopt canonical attribute names (`icao_code`, not `ICAO_CODE`). |
| **Error Handling** | Rescue per-row errors; log but continue. |
| **Extensibility** | Adding a new source = new subclass + tests; no schema change. |

### 4.3 Trust & Provenance

The combine phase uses a **per-field trust system** to select the best value when multiple sources provide conflicting data.

#### 4.3.1 Field Provenance

Each canonical record stores provenance metadata in a `field_provenance` JSONB column:

```json
{
  "name": {
    "source_type": "OpenTravelOperatorSource",
    "source_id": 456,
    "confidence": 85,
    "combined_at": "2024-12-24T10:30:00Z"
  },
  "icao_code": {
    "source_type": "VRSDataOperatorSource",
    "source_id": 123,
    "confidence": 80,
    "combined_at": "2024-12-24T08:00:00Z"
  }
}
```

Note: The actual field value is stored in the canonical column itself; the provenance tracks *where* it came from.

This enables:
- Debugging why a field has a particular value (trace back to source record)
- Displaying source attribution in the UI
- Re-combining with updated trust rules without data loss
- Finding records by their data sources (e.g., `Airport.with_field_source(:name, 'OurAirportsAirportSource')`)

#### 4.3.2 Trust Configuration

Trust scores are configured via the `source_trust_scores` table:

| Column        | Type              | Purpose                                            |
|---------------|-------------------|----------------------------------------------------|
| `entity_type` | string            | Canonical model name (e.g., "Operator")            |
| `source_type` | string            | Source class name (e.g., "VRSDataOperatorSource")  |
| `field_name`  | string (nullable) | Specific field, or `null` for source-wide default |
| `base_trust`  | integer           | Trust score 0-100                                  |

Field-specific entries override source-wide defaults. Example:

```
entity_type: Operator, source_type: CASAAircraftSource, field_name: null,     base_trust: 85
entity_type: Operator, source_type: CASAAircraftSource, field_name: operator, base_trust: 40
```

This says: "CASA is generally 85% trustworthy, but only 40% for operator names."

#### 4.3.3 Confidence Modifiers

Source trust configuration is centralised in `app/models/source_config.rb`:

```ruby
class SourceConfig
  CONFIGS = {
    'CASAAircraftSource' => {
      base_trust: 85,
      field_overrides: { operator: 40, owner: 40 },
      modifiers: {
        icao: {
          filter: ->(r) { r.icao&.match?(/\A7C/) },
          adjust: ->(trust) { [trust + 10, 100].min }
        }
      }
    },
    'VRSDataOperatorSource' => {
      base_trust: 80,
      field_overrides: {},
      modifiers: {}
    },
    'OpenTravelOperatorSource' => {
      base_trust: 70,
      field_overrides: { name: 85 },  # OpenTravel has better names
      modifiers: {}
    }
  }.freeze

  def self.for(source_class_name)
    CONFIGS[source_class_name] || { base_trust: 50, field_overrides: {}, modifiers: {} }
  end
end
```

This centralised approach makes it easy to compare trust scores across sources and understand which source wins for each field.

The combine algorithm applies trust in this order:
1. Look up base trust from `source_trust_scores` table (database, tunable)
2. Fall back to `SourceConfig.for(source)[:base_trust]` if not in DB
3. Apply `field_overrides` for specific fields
4. Apply `modifiers` if filter matches
5. Compare across sources; highest confidence wins per field

#### 4.3.4 User Contributions

User-submitted corrections are stored in `user_contributions` and treated as a source type:

| Column        | Type   | Purpose                           |
|---------------|--------|-----------------------------------|
| `user_id`     | FK     | Contributing user                 |
| `entity_type` | string | Target model                      |
| `entity_id`   | bigint | Target record ID                  |
| `field_name`  | string | Field being corrected             |
| `old_value`   | jsonb  | Previous value (for audit)        |
| `new_value`   | jsonb  | Proposed value                    |
| `status`      | enum   | `pending`, `approved`, `rejected` |
| `notes`       | text   | Optional justification            |

Users have a `contribution_trust` score (0-100). High-trust users (e.g., 90+) may have contributions auto-applied; others require review.

---

## 5 Northbound API (`/api/v1`)

* **Format:** JSON:API 1.1 (camel-case links, snake-case attributes).
* **Auth:** optional read-only; JWT (`knock` gem) for high-rate or write ops.
* **Pagination:** `Pagy::Cursor` (`Link` header).
* **Filtering:** `?filter[icao]=...`; full-text via Meilisearch.
* **Errors:** RFC 9457 `application/problem+json`.
* **Rate-limit:** Rack-Attack (100 req/min default).

| Verb | Path | Purpose |
|------|------|---------|
| `GET` | `/aircraft` | List; filter by `icao`, `registration`, `operator_id` |
| `GET` | `/aircraft/:id` | Details + associations |
| `GET` | `/operators` / `:id` | |
| `GET` | `/airports` / `:id` | |
| `GET` | `/routes/:id/segments` | Route structure |

---

## 6 Web UI

* **Stack:** Hotwire (Turbo & Stimulus), Tailwind CSS, ViewComponent.
* **Features:**
  * Global instant search (Meilisearch).
  * Entity index & detail views with breadcrumbs.
  * Import dashboard (last 30 runs, diff visualiser).
  * Admin CRUD via `administrate`.
* **UX:** Responsive, dark-mode default, WCAG 2.1 AA.

---

## 7 Cross-Cutting Concerns

| Topic | Tooling / Practice |
|-------|-------------------|
| **Style** | `rubocop` + `StandardRB`; enforced in CI; `annotate` gem used to add DB Schema to model files. |
| **Testing** | RSpec, FactoryBot, Shoulda-Matchers, VCR (HTTP fixtures). 90 % coverage target. |
| **CI/CD** | GitHub Actions → lint → test → build image → deploy (Fly.io / Helm). |
| **Security** | Devise auth, Pundit policies, Brakeman scan. |
| **Performance** | Bullet (N+1), query indices, Redis caching. |
| **Search** | `meilisearch-rails`; nightly full reindex. |
| **Observability** | Lograge JSON, StatsD, Sidekiq-Prometheus, `/healthz`. |
| **I18n** | Default `en`; YAML locale files ready. |
| **GDPR** | PaperTrail + cascade deletes honour right-to-be-forgotten. |

---

## 8 Directory & Naming Conventions

```text
app/
  models/                    # ActiveRecord + business logic
    concerns/                # Shared AR concerns
    processors/              # ETL classes (import/combine)
    source/                  # Raw source record models (STI)
    source_config.rb         # Centralised trust configuration
  services/                  # Service objects (TrustCalculator, FieldMerger)
  controllers/               # API & UI endpoints
  serializers/               # JSON-API objects
  components/                # ViewComponent
config/
  sidekiq.yml
  initializers/
test/
  models/processors/         # VCR-backed specs per processor
```

* Classes: **Singular CamelCase** (`IcaoAircraftProcessor`).
* Tables: plural snake_case (`aircraft_types`).
* Source tables: `<canonical>_sources`.
* Specs mirror class names (`icao_aircraft_processor_spec.rb`).

---

## 9 Contribution Guide (abridged)

1. Fork & branch (`feat/xyz`), commit style `type(scope): subject`.
2. Ensure `bin/rspec` & `rubocop -A` pass locally.
3. Add VCR fixtures for new processors.
4. PR → CI green → review → squash-merge.

