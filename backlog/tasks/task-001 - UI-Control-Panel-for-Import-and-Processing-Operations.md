---
id: task-001
title: UI Control Panel for Import and Processing Operations
status: To Do
assignee: []
created_date: '2025-12-30 08:37'
updated_date: '2025-12-31 05:00'
labels:
  - feature
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Requirements:

- web interface that enables an operator to: 
    - trigger an import on a given model and all it's sources or a subset of it's sources (down to a single source import). 
    - trigger a processing / combining operation on a given model's sources
    - show the output results of a given import or processor / combining operation including errors.
    - schedule import and process/combine operations to occur in the future at regular intervals
    - view previous import and process/combine operations and their output and errors.
- the interface should log actions taken by users - e.g. manually triggered import/processing/combining operations should be logged against the user that triggered it. 
- the audit log should be visible in the UI.
- the web interfaces should follow the existing style and themes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard displays all importable models with available sources grouped by entity type
- [ ] #2 Individual source import buttons trigger DataImportJob for specific processor
- [ ] #3 Import All button per model triggers all sources for that model
- [ ] #4 Combine buttons trigger DataCombineJob for each canonical model (processing = combining)
- [ ] #5 Sync All button triggers full pipeline (imports then combines in dependency order)
- [ ] #6 Running operations display real-time status via Turbo Streams
- [ ] #7 Completed operations show records processed/created/updated counts
- [ ] #8 Failed operations display error details and stack traces
- [ ] #9 Users can click into an operation to see full output log and error details
- [ ] #10 Operation history is paginated and filterable by status/type/model
- [ ] #11 Source exclusions UI allows browsing sources by STI type
- [ ] #12 Source records can be marked as excluded with reason (uses HasSourceExclusion)
- [ ] #13 Excluded records can be re-included
- [ ] #14 Trust score overrides can be CRUD'd by admins (SourceTrustScore model)
- [ ] #15 Trust score changes call SourceTrustScore.clear_cache!
- [ ] #16 Conflict dashboard shows count summary by entity type and field
- [ ] #17 Conflict detail view shows all candidate values with trust scores from FieldMerger
- [ ] #18 Conflicts can be marked as resolved or ignored
- [ ] #19 Scheduled operations support cron expressions via fugit gem
- [ ] #20 Schedules can be enabled/disabled
- [ ] #21 Schedules show next run time and last run status
- [ ] #22 All admin actions logged to AdminAuditLog
- [ ] #23 Audit log viewable with filtering by user/action/date
- [ ] #24 Three-tier role system: admin (full), operator (trigger only), viewer (read-only)

- [ ] #25 Operators can trigger operations but cannot manage schedules/exclusions/trust
- [ ] #26 Viewers have read-only access to all panels
- [ ] #27 UI follows existing Tailwind dark sidebar theme
- [ ] #28 Admin navigation added to sidebar (Operations section)

- [ ] #29 Mobile responsive design
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# UI Control Panel for Import and Processing Operations

## Overview

Build a web-based admin control panel for managing the two-phase data pipeline (Import → Combine) with:
- Granular import/combine controls + "Sync All" convenience
- Source exclusion management
- Trust score configuration UI
- Conflict dashboard
- Scheduled operations
- Audit logging
- Role-based access (admin/operator/viewer)
- Real-time updates via Turbo Streams

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Background Jobs | Solid Queue | Rails 8 native, database-backed, built-in recurring jobs |
| Authorisation | Custom policy classes | Lightweight, fits simple 3-tier model |
| Real-time | Turbo Streams + ActionCable | Already in stack |
| Audit Logging | Custom model | Simple requirements, full control |
| Cron Parsing | `fugit` gem | Lightweight, well-maintained |

## Dependencies

```ruby
gem 'solid_queue'
gem 'fugit'
```

---

## Phase 1: Database Schema

### 1.1 Add role to users
```ruby
add_column :users, :role, :string, default: 'viewer', null: false
# Values: 'admin', 'operator', 'viewer'
```

### 1.2 Create `data_operations` table
Tracks all import/combine job executions.

| Column | Type | Notes |
|--------|------|-------|
| operation_type | string | 'import', 'combine', 'sync_all' |
| processor_class | string | e.g., 'Processors::Operator::VrsData' |
| target_model | string | For combine: 'Operator', 'Aircraft', etc. |
| source_name | string | For import: 'VRS', 'CASA', etc. |
| status | string | pending/running/completed/failed/cancelled |
| started_at, completed_at | datetime | |
| records_processed, records_created, records_updated | integer | |
| errors | jsonb | Array of error details |
| conflicts | jsonb | Array of conflict details |
| output_log | text | Captured console output |
| user_id | fk | Who triggered |
| parent_operation_id | fk | For batch operations |

### 1.3 Create `operation_schedules` table
Cron-based scheduling configuration.

| Column | Type | Notes |
|--------|------|-------|
| name | string | User-friendly name |
| processor_class | string | |
| operation_type | string | |
| cron_expression | string | e.g., '0 2 * * *' |
| enabled | boolean | |
| last_run_at, next_run_at | datetime | |
| created_by_id | fk | |

### 1.4 Create `admin_audit_logs` table

| Column | Type | Notes |
|--------|------|-------|
| user_id | fk | |
| action | string | e.g., 'trigger_import', 'exclude_source' |
| resource_type | string | Polymorphic |
| resource_id | bigint | |
| changes | jsonb | Before/after values |
| ip_address, user_agent | string | |

### 1.5 Create `data_conflicts` table
Persistent conflict tracking from combine operations.

| Column | Type | Notes |
|--------|------|-------|
| entity_type | string | 'Aircraft', 'Operator', etc. |
| entity_identifier | string | ICAO or unique ID |
| field_name | string | |
| candidates | jsonb | Array of source values with trust scores |
| winner_source_type | string | |
| winner_value | jsonb | |
| status | string | active/resolved/ignored |
| resolved_by_id | fk | |
| data_operation_id | fk | Which combine detected this |

---

## Phase 2: Models

### New Models

- `DataOperation` - Job execution tracking with status transitions
- `OperationSchedule` - Cron scheduling with `fugit` parsing
- `AdminAuditLog` - Action logging with `log!` class method
- `DataConflict` - Conflict persistence with `create_from_combine!`

### User Model Updates

Add role enum and helper methods:
```ruby
ROLES = %w[admin operator viewer].freeze

def admin?
def operator?  # includes admin
def can_trigger_operations?  # operator+
def can_manage_config?  # admin only
def can_manage_exclusions?  # admin only
```

---

## Phase 3: Processor Registry Service

Create `app/services/processor_registry.rb` to centralise processor metadata.

**Import Processors** (source → source table):
- `Processors::Aircraft::Casa::Registry` → CASA
- `Processors::Aircraft::Caanz::Registry` → CAANZ
- `Processors::Aircraft::Opensky` → OpenSky
- `Processors::Aircraft::Vrs::StandingData` → VRS
- `Processors::AircraftType::CfappsIcaoInt` → ICAO
- `Processors::AircraftType::OpenFlights` → OpenFlights
- `Processors::AircraftType::Vrs::ModelType` → VRS
- `Processors::Operator::VrsData` → VRS
- `Processors::Operator::OpenTravel` → OpenTravel
- `Processors::Operator::OpenFlights` → OpenFlights
- `Processors::Operator::AirlineCodes` → AirlineCodes
- `Processors::Airport::OurAirports` → OurAirports
- `Processors::Airport::OpenFlights` → OpenFlights
- `Processors::Country::OpenTravel` → OpenTravel
- `Processors::Country::OpenFlights` → OpenFlights
- `Processors::Country::OurAirports` → OurAirports
- `Processors::Manufacturer::CfappsIcaoInt` → ICAO
- `Processors::Runway::OurAirports` → OurAirports

**Combine Processors** (source table → canonical):
- `Processors::Country::Country`
- `Processors::Manufacturer::Manufacturer`
- `Processors::Operator::Operator`
- `Processors::AircraftType::AircraftType`
- `Processors::Airport::Airport`
- `Processors::Runway::Runway`
- `Processors::Aircraft::Aircraft`

---

## Phase 4: Background Jobs

### 4.1 Configure Solid Queue

```yaml
# config/solid_queue.yml
production:
  workers:
    - queues: [imports, combines]
      threads: 2
    - queues: [default]
      threads: 3
```

### 4.2 Job Classes

**`DataImportJob`** (queue: imports)
- Calls `processor_class.constantize.import`
- Broadcasts status via Turbo Streams
- Creates `SourceImportReport` (existing pattern)

**`DataCombineJob`** (queue: combines)
- Calls `processor_class.constantize.combine_sources`
- Captures conflicts from `FieldMerger`
- Persists to `DataConflict` table

**`SyncAllJob`** (queue: default)
- Creates child `DataOperation` records
- Executes imports then combines in dependency order
- Tracks overall progress

**`ScheduledOperationJob`** (recurring)
- Checks `OperationSchedule.due`
- Enqueues appropriate jobs
- Updates `last_run_at` / `next_run_at`

---

## Phase 5: Controllers & Routes

### Routes (admin namespace)

```ruby
namespace :admin do
  root to: 'dashboard#index'

  resources :operations, only: [:index, :show, :create] do
    collection { post :sync_all }
    member { post :cancel }
  end

  resources :source_exclusions, only: [:index, :update, :destroy] do
    collection { get :by_type }
  end

  resources :trust_scores, only: [:index, :create, :update, :destroy]

  resources :conflicts, only: [:index, :show] do
    member { post :resolve; post :ignore }
  end

  resources :schedules, except: [:show]
  resources :audit_logs, only: [:index]
end
```

### Controllers

| Controller | Access | Purpose |
|------------|--------|---------|
| `Admin::BaseController` | All authenticated | Common auth, authorisation, auditing |
| `Admin::DashboardController` | viewer+ | Overview, quick actions |
| `Admin::OperationsController` | operator+ for create | Trigger/view operations |
| `Admin::SourceExclusionsController` | admin for modify | Manage source exclusions |
| `Admin::TrustScoresController` | admin for modify | Manage SourceTrustScore overrides |
| `Admin::ConflictsController` | viewer+ | View/resolve conflicts |
| `Admin::SchedulesController` | admin only | Manage cron schedules |
| `Admin::AuditLogsController` | viewer+ | View audit trail |

---

## Phase 6: Views

### Dashboard (`admin/dashboard/index`)
- **Running Operations Alert** - if any running
- **Stats Grid** - source count, canonical count, conflict count, ops today
- **Import Controls Panel** - grouped by model, individual source buttons
- **Combine Controls Panel** - one button per model
- **Sync All Button** - triggers full pipeline
- **Conflict Summary** - counts by entity type
- **Recent Operations** - last 10 with status badges

### Operations Index/Show
- Filterable table with status/type/model filters
- Detail view with output log, errors, conflicts
- Re-run and cancel actions

### Source Exclusions
- Browse sources by type
- Mark excluded with reason
- Re-include button

### Trust Scores
- Show SourceConfig defaults
- CRUD for SourceTrustScore overrides
- Clear cache on modification

### Conflicts
- Summary by entity type and field
- Detail view showing all candidate values
- Resolve/ignore actions

### Schedules
- CRUD with cron builder
- Enable/disable toggle
- Next run time display

---

## Phase 7: Real-time Updates

### ActionCable Channel
`AdminOperationsChannel` - streams operation status updates

### Turbo Stream Broadcasts
- `DataOperation` broadcasts on status change
- Target: `operation_#{id}` partial

### Stimulus Controllers
- `operation_status_controller.js` - polling fallback
- `source_exclusion_controller.js` - inline actions
- `cron_builder_controller.js` - cron expression helper

---

## Phase 8: Authorisation

Custom policy classes (no Pundit gem):

```ruby
class DataOperationPolicy
  def create? = user.operator?
  def cancel? = user.admin? || (user.operator? && operation.user == user)
end

class SourceTrustScorePolicy
  def create? = user.admin?
  def update? = user.admin?
end
```

---

## File Structure

```
app/
├── channels/
│   └── admin_operations_channel.rb
├── controllers/admin/
│   ├── base_controller.rb
│   ├── dashboard_controller.rb
│   ├── operations_controller.rb
│   ├── source_exclusions_controller.rb
│   ├── trust_scores_controller.rb
│   ├── conflicts_controller.rb
│   ├── schedules_controller.rb
│   └── audit_logs_controller.rb
├── jobs/
│   ├── data_import_job.rb
│   ├── data_combine_job.rb
│   ├── sync_all_job.rb
│   └── scheduled_operation_job.rb
├── models/
│   ├── data_operation.rb
│   ├── operation_schedule.rb
│   ├── admin_audit_log.rb
│   └── data_conflict.rb
├── policies/
│   ├── data_operation_policy.rb
│   └── source_trust_score_policy.rb
├── services/
│   └── processor_registry.rb
├── views/admin/
│   ├── dashboard/
│   ├── operations/
│   ├── source_exclusions/
│   ├── trust_scores/
│   ├── conflicts/
│   ├── schedules/
│   └── audit_logs/
└── javascript/controllers/
    ├── operation_status_controller.js
    └── cron_builder_controller.js

db/migrate/
├── XXXXXX_add_role_to_users.rb
├── XXXXXX_create_data_operations.rb
├── XXXXXX_create_operation_schedules.rb
├── XXXXXX_create_admin_audit_logs.rb
└── XXXXXX_create_data_conflicts.rb
```

---

## Integration Points

### Processor Integration
Jobs call existing processor methods directly:
```ruby
# Import
processor_class.constantize.import

# Combine
processor_class.constantize.combine_sources
```

### Conflict Capture
Modify `Processors::Base` to expose conflicts:
```ruby
class << self
  attr_accessor :last_conflicts
end
```

### Source Exclusion
Use existing `HasSourceExclusion` concern methods:
```ruby
source.exclude!(reason:, by:)
source.include!
```

### Trust Score
Use existing `SourceTrustScore` with `clear_cache!` after changes.

---

## Critical Files to Modify

1. `app/models/user.rb` - Add role
2. `config/routes.rb` - Add admin namespace
3. `app/views/layouts/application.html.erb` - Reference for admin layout styling
4. `app/models/processors/base.rb` - Add conflict capture hook

## Critical Files to Create

1. `db/migrate/*` - 5 migrations
2. `app/models/data_operation.rb`
3. `app/models/operation_schedule.rb`
4. `app/models/admin_audit_log.rb`
5. `app/models/data_conflict.rb`
6. `app/services/processor_registry.rb`
7. `app/controllers/admin/base_controller.rb`
8. `app/controllers/admin/dashboard_controller.rb`
9. `app/controllers/admin/operations_controller.rb`
10. `app/jobs/data_import_job.rb`
11. `app/jobs/data_combine_job.rb`
12. `app/views/layouts/admin.html.erb`
13. `app/views/admin/dashboard/index.html.erb`
14. `config/solid_queue.yml`

---

## Implementation Order

1. **Migrations & Models** - Foundation
2. **ProcessorRegistry** - Required for UI
3. **Solid Queue setup** - Job infrastructure
4. **Admin layout & dashboard** - UI shell
5. **Operations controller & jobs** - Core functionality
6. **Source exclusions UI** - Data quality
7. **Trust scores UI** - Configuration
8. **Conflicts UI** - Review workflow
9. **Schedules** - Automation
10. **Audit logs** - Compliance
11. **Real-time updates** - Polish
<!-- SECTION:PLAN:END -->
