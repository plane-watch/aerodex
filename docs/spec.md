
# Aerodex – Project Specification  
*v0.5 — 2025-07-05 (Australia/Sydney)*  

---

## 1 Purpose & Scope  

Aerodex is a **Ruby on Rails** monolith that provides a **free, open registry of aviation metadata** for:

* **Plane‑Watch** (`https://app.plane.watch`) — interactive flight‑tracking UI.  
* **Third‑party consumers** via a versioned JSON/REST API.  

The app:  

1. **Ingests** data from heterogeneous public sources (CSV, JSON, XML, HTML scrapes, REST APIs).  
2. **Normalises & deduplicates** feeds into a **canonical domain model** (Aircraft, Operator, Route, …).  
3. **Serves** the consolidated data through:  
   * A **Hotwire/Tailwind** web UI.  
   * A **northbound REST API** (`/api/v1`).  
4. **Audits & traces** every field back to its upstream source.  

---

## 2 Architecture Overview  

```text
Web UI (Hotwire/Turbo) ──► Northbound API (REST/JSON) ──► Domain Models (PostgreSQL)
                                      ▲                         │
                                      │                         ▼
                             Processor Framework (ETL) ◄── Sidekiq Jobs
                                      │
                             External Data Sources
```

| Layer | Duties | Tech / Gems |
|-------|--------|------------|
| **UI** | Browsing, search, admin dashboards | Hotwire, ViewComponent, Tailwind CSS |
| **API** | Versioned JSON, pagination, filtering | Rails controllers, `pagy`, `active_model_serializers` |
| **Domain Models** | Canonical entities, validations, audit | ActiveRecord, PaperTrail, Meilisearch |
| **Processors** | Fetch → parse → merge → report | POROs in `lib/processors`, `http`, `csv`, `nokogiri` |
| **Jobs** | Schedule and execute imports | Sidekiq + Sidekiq‑Cron |
| **Storage** | Primary data, search, file blobs | PostgreSQL, Meilisearch, S3/MinIO |

---

## 3 Canonical Domain Model (abridged)

The fields listed below are preliminary, they may change as the project evolves. 

| Model | Key Attributes | Notes |
|-------|----------------|-------|
| **Aircraft** | `icao` (mode‑S), `registration`, `serial_number`, `aircraft_type_id`, `operator_id`, `status` (enum) | Indexed on `icao`, `registration` |
| **AircraftType** | `name`, `type_code` (ICAO), `category` (enum), `manufacturer_id` | |
| **Manufacturer** | `name`, `icao_code`, `country_id`, `alt_names` (jsonb) | |
| **Operator** | `name`, `icao_code`, `iata_code`, `country_id` | |
| **Airport** | `iata_code`, `icao_code`, `latitude`, `longitude`, `country_id` | |
| **Route** | `operator_id`, `call_sign`; has many **RouteSegments** | |
| **RouteSegment** | `route_id`, `airport_id`, `sequence`, `sta`, `std` | |
| **Country** | ISO‑3166 codes, `name`, `capital` | |
| **Source** | `type`, `imported_at`, `data` (jsonb raw blob) | One row per upstream record |
| **SourceImportReport** | `importer_type`, `processed_count`, `error_count`, `details` (jsonb) | Summarises each ETL run |

All canonical tables include `created_at`, `updated_at` and are versioned via **PaperTrail**.

---

## 4 Processor Framework  

**Location:** `lib/processors`  

```ruby
class BaseProcessor
  # Download / parse upstream and persist raw Source rows.
  # @return [Array<Source>]
  def import!;  raise NotImplementedError; end

  # Merge multiple Source rows into canonical models.
  # @return [Integer] count of canonical rows touched
  def combine!; raise NotImplementedError; end
end
```

### 4.1 Workflow  

1. **Fetch** — stream remote file or API.  
2. **Parse** — convert to enumerable of hashes.  
3. **Upsert Source** — `*_sources` table (`UPSERT` by primary key).  
4. **Combine** — deterministic priority rules, fuzzy matching helpers (Trigram similarity).  
5. **Report** — create `SourceImportReport` with metrics & errors.  

**Sidekiq** workers execute imports; long jobs split by source to keep queue latency low.

### 4.2 Guidelines  

| Concern | Guideline |
|---------|-----------|
| **Scalability** | Stream files >50 MB, use `COPY` for bulk inserts. |
| **Idempotency** | Importers re‑runnable without side‑effects (UPSERT only). |
| **Traceability** | Persist original row JSON, reference canonical via FK. |
| **Naming** | Adopt canonical attribute names (`icao_code`, not `ICAO_CODE`). |
| **Error Handling** | Rescue per‑row errors; log but continue. |
| **Extensibility** | Adding a new source = new subclass + tests; no schema change. |

---

## 5 Northbound API (`/api/v1`)  

* **Format:** JSON:API 1.1 (camel‑case links, snake‑case attributes).  
* **Auth:** optional read‑only; JWT (`knock` gem) for high‑rate or write ops.  
* **Pagination:** `Pagy::Cursor` (`Link` header).  
* **Filtering:** `?filter[icao]=...`; full‑text via Meilisearch.  
* **Errors:** RFC 9457 `application/problem+json`.  
* **Rate‑limit:** Rack‑Attack (100 req/min default).  

| Verb | Path | Purpose |
|------|------|---------|
| `GET` | `/aircraft` | List; filter by `icao`, `registration`, `operator_id` |
| `GET` | `/aircraft/:id` | Details + associations |
| `GET` | `/operators` / `:id` | | 
| `GET` | `/airports` / `:id` | | 
| `GET` | `/routes/:id/segments` | Route structure |

---

## 6 Web UI  

* **Stack:** Hotwire (Turbo & Stimulus), Tailwind CSS, ViewComponent.  
* **Features:**  
  * Global instant search (Meilisearch).  
  * Entity index & detail views with breadcrumbs.  
  * Import dashboard (last 30 runs, diff visualiser).  
  * Admin CRUD via `administrate`.  
* **UX:** Responsive, dark‑mode default, WCAG 2.1 AA.

---

## 7 Cross‑Cutting Concerns  

| Topic | Tooling / Practice |
|-------|-------------------|
| **Style** | `rubocop` + `StandardRB`; enforced in CI; `annotate` gem used to add DB Schema to model files. |
| **Testing** | RSpec, FactoryBot, Shoulda‑Matchers, VCR (HTTP fixtures). 90 % coverage target. |
| **CI/CD** | GitHub Actions → lint → test → build image → deploy (Fly.io / Helm). |
| **Security** | Devise auth, Pundit policies, Brakeman scan. |
| **Performance** | Bullet (N+1), query indices, Redis caching. |
| **Search** | `meilisearch‑rails`; nightly full reindex. |
| **Observability** | Lograge JSON, StatsD, Sidekiq‑Prometheus, `/healthz`. |
| **I18n** | Default `en`; YAML locale files ready. |
| **GDPR** | PaperTrail + cascade deletes honour right‑to‑be‑forgotten. |

---

## 8 Directory & Naming Conventions  

```text
app/
  models/          # ActiveRecord + business logic
  controllers/     # API & UI endpoints
  serializers/     # JSON‑API objects
  components/      # ViewComponent
lib/
  processors/      # ETL classes (one per source)
config/
  sidekiq.yml
  initializers/
test/
  processors/      # VCR‑backed specs per source
```

* Classes: **Singular CamelCase** (`IcaoAircraftProcessor`).  
* Tables: plural snake_case (`aircraft_types`).  
* Source tables: `<canonical>_sources`.  
* Specs mirror class names (`icao_aircraft_processor_spec.rb`).  

---

## 9 Contribution Guide (abridged)

1. Fork & branch (`feat/xyz`), commit style `type(scope): subject`.  
2. Ensure `bin/rspec` & `rubocop -A` pass locally.  
3. Add VCR fixtures for new processors.  
4. PR → CI green → review → squash‑merge.  

