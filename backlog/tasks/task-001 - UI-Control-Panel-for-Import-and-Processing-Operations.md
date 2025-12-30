---
id: task-001
title: UI Control Panel for Import and Processing Operations
status: To Do
assignee: []
created_date: '2025-12-30 08:37'
updated_date: '2025-12-30 08:50'
labels:
  - feature
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## EXAMPLE

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
- [ ] #1 Dashboard view displays all importable models with their available data sources
- [ ] #2 User can trigger import on a single source with one click
- [ ] #3 User can trigger import on all sources for a model with one click
- [ ] #4 User can trigger processing/combining operation on a model (stubbed)
- [ ] #5 Running jobs display progress bar with real-time updates via Turbo Streams
- [ ] #6 Completed jobs show summary (records processed, duration, success/fail)
- [ ] #7 Failed jobs display detailed error information with per-record errors
- [ ] #8 Users can view paginated history of all import/processing operations
- [ ] #9 Users can filter job history by status, model type, and source
- [ ] #10 Users can click into a job to see full output and error details
- [ ] #11 Scheduled operations can be created with cron expressions
- [ ] #12 Scheduled operations can be enabled/disabled
- [ ] #13 Scheduled operations automatically trigger at specified times
- [ ] #14 Scheduled operations show next run time and last run status
- [ ] #15 All manual triggers are logged in audit log with user attribution
- [ ] #16 All schedule changes are logged in audit log
- [ ] #17 Audit log is viewable in UI with filtering by user/action/date
- [ ] #18 Three-tier role system: admin (full access), operator (trigger only), viewer (read-only)
- [ ] #19 Operators cannot access schedule management (admin only)
- [ ] #20 Viewers can only see job history and audit logs (read-only)
- [ ] #21 UI follows existing Tailwind dark sidebar theme
- [ ] #22 Navigation includes new 'Operations' section with appropriate sub-items
- [ ] #23 Mobile responsive: job list hides non-essential columns on small screens
- [ ] #24 Real-time job status updates without page refresh
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation Plan

### Phase 1: Foundation (Database & Models)

#### 1.1 Add Role System to Users
- Add `role` enum column to `users` table with values: `viewer`, `operator`, `admin`
- Default new users to `viewer`
- Update `User` model with role enum and helper methods (`admin?`, `operator?`, `viewer?`, `can_trigger_operations?`, `can_manage_schedules?`)

#### 1.2 Create Operation Job Tracking
Create `operation_jobs` table to track all import/processing operations:
- `id`, `user_id` (foreign key - who triggered)
- `job_type` enum: `import`, `process`, `combine`
- `model_type` string (e.g., "Aircraft", "Manufacturer", "Operator")
- `source_type` string (e.g., "Processors::Aircraft::CASA::Registry")
- `status` enum: `pending`, `queued`, `running`, `completed`, `failed`
- `progress` integer (0-100 for progress tracking)
- `started_at`, `completed_at` timestamps
- `results` JSONB (records_processed, errors, warnings, summary)
- `error_message` text (for failed jobs)
- `scheduled_operation_id` (nullable FK - if triggered by schedule)
- `created_at`, `updated_at`

Model: `OperationJob` with:
- Associations: `belongs_to :user`, `belongs_to :scheduled_operation` (optional)
- Scopes: `recent`, `by_status`, `by_model`, `by_source`
- Status transition methods
- Meilisearch indexing for searchable history

#### 1.3 Create Scheduled Operations
Create `scheduled_operations` table:
- `id`, `name` string (user-friendly name)
- `job_type` enum: `import`, `process`, `combine`
- `model_type` string
- `source_type` string (nullable for "all sources")
- `cron_expression` string (e.g., "0 2 * * *" for 2am daily)
- `enabled` boolean (default true)
- `last_run_at` timestamp
- `next_run_at` timestamp
- `created_by_id` FK to users
- `created_at`, `updated_at`

Model: `ScheduledOperation` with:
- Associations: `belongs_to :created_by, class_name: 'User'`, `has_many :operation_jobs`
- Validation for cron expression
- Methods: `calculate_next_run`, `due?`

#### 1.4 Create Audit Log
Create `audit_logs` table:
- `id`, `user_id` FK
- `action` string (e.g., "trigger_import", "create_schedule", "cancel_job")
- `auditable_type` string (polymorphic)
- `auditable_id` bigint
- `details` JSONB (context-specific data)
- `ip_address` string
- `user_agent` string
- `created_at`

Model: `AuditLog` with:
- Associations: `belongs_to :user`, `belongs_to :auditable, polymorphic: true`
- Scopes for filtering by user, action, date range
- Class methods for creating common audit entries

---

### Phase 2: Background Job Infrastructure

#### 2.1 Configure Solid Queue
- Add `solid_queue` gem to Gemfile
- Run `bin/rails solid_queue:install`
- Configure `config/solid_queue.yml` with queues: `default`, `imports`, `processing`, `scheduling`
- Update `config/application.rb` to use Solid Queue as ActiveJob adapter
- Create database migrations for Solid Queue tables

#### 2.2 Create Job Classes

**ImportSourceJob** (`app/jobs/import_source_job.rb`):
- Takes `operation_job_id` as argument
- Updates status to `running`, sets `started_at`
- Calls stubbed processor method (to be integrated later)
- Broadcasts progress via Turbo Streams
- Updates status to `completed`/`failed` with results
- Creates audit log entry

**ProcessSourceJob** (`app/jobs/process_source_job.rb`):
- Similar structure for processing/combining operations
- Stubbed implementation

**ScheduledOperationRunnerJob** (`app/jobs/scheduled_operation_runner_job.rb`):
- Recurring job that checks for due scheduled operations
- Creates OperationJob records and enqueues appropriate jobs
- Updates `last_run_at` and `next_run_at`

---

### Phase 3: Controllers & Authorization

#### 3.1 Authorization Layer
Create `app/policies/` with Pundit-style authorization:
- `ApplicationPolicy` base class
- `OperationJobPolicy` - viewer: read, operator: trigger, admin: all
- `ScheduledOperationPolicy` - viewer: read, operator: read, admin: CRUD
- `AuditLogPolicy` - viewer: none, operator: read own, admin: read all

Add `Authorizable` concern to ApplicationController with:
- `authorize!` method
- `current_user_role` helper
- Access denied handling

#### 3.2 Admin Namespace Controllers

**Admin::DashboardController** (`index`):
- Overview of available models/sources
- Quick action buttons for triggering operations
- Recent job activity summary
- System status (queue depth, running jobs)

**Admin::OperationJobsController** (`index`, `show`, `create`, `cancel`):
- `index`: Filterable list of all operation jobs with status
- `show`: Detailed view of single job with output/errors
- `create`: Trigger new import/process operation (creates OperationJob, enqueues job)
- `cancel`: Cancel a pending/running job

**Admin::ScheduledOperationsController** (full CRUD):
- List all scheduled operations
- Create/edit schedule with cron builder UI
- Enable/disable schedules
- View execution history per schedule

**Admin::AuditLogsController** (`index`):
- Searchable/filterable audit log viewer
- Export capability (CSV)

---

### Phase 4: Real-Time Updates with Turbo Streams

#### 4.1 ActionCable Channel
Create `OperationJobChannel`:
- Stream updates for specific job or all jobs
- Broadcast: status changes, progress updates, completion

#### 4.2 Turbo Stream Broadcasts
In `OperationJob` model:
- `after_update_commit` broadcasts to update job row in list
- `after_update_commit` broadcasts to update job detail view
- Progress updates broadcast percentage changes

#### 4.3 Stimulus Controllers
- `job_progress_controller.js` - Handles progress bar updates
- `auto_refresh_controller.js` - Polls for updates (fallback)
- `job_actions_controller.js` - Trigger/cancel actions with confirmation

---

### Phase 5: Views & UI

#### 5.1 Navigation Update
Add "Operations" section to sidebar (visible to operator/admin roles):
- Dashboard
- Import Jobs
- Schedules (admin only)
- Audit Log

#### 5.2 Dashboard View (`admin/dashboard/index.html.erb`)
Layout: Card-based grid showing:
- **Models Panel**: Accordion of importable models (Aircraft, Manufacturer, Operator, etc.)
  - Each model expands to show available sources
  - "Import All" button per model
  - Individual source import buttons
  - Last import status/date per source
- **Active Jobs Panel**: Currently running jobs with progress bars
- **Recent Activity Panel**: Last 10 completed jobs with status badges
- **Scheduled Jobs Panel**: Upcoming scheduled operations

#### 5.3 Operation Jobs Index (`admin/operation_jobs/index.html.erb`)
- Filterable table (Turbo Frame for filtering without full reload)
- Columns: ID, Type, Model, Source, Status (badge), Started, Duration, Triggered By
- Row click → show detail
- Status filter tabs: All, Running, Completed, Failed
- Search by model/source
- Pagination (Pagy)

#### 5.4 Operation Job Show (`admin/operation_jobs/show.html.erb`)
- Header with job metadata and status badge
- Progress bar (for running jobs)
- Tabs:
  - **Summary**: Records processed, success/fail counts, duration
  - **Output**: Scrollable log output
  - **Errors**: Expandable list of individual errors with details
- Actions: Re-run (creates new job with same params), Cancel (if running)

#### 5.5 Scheduled Operations Views
- Index: Table with name, type, cron (human readable), next run, status toggle
- Form: Name, job type selector, model selector, source selector, cron builder
- Cron builder: Visual interface for common patterns (daily, weekly, custom)

#### 5.6 Audit Log View
- Table: Timestamp, User, Action, Target, Details (expandable)
- Filters: Date range, user, action type
- Export button

#### 5.7 Styling
- Follow existing Tailwind dark sidebar theme
- Use existing status badge patterns from aircraft list
- FontAwesome icons consistent with navigation
- Responsive design (hide columns on mobile)

---

### Phase 6: Model & Source Registry

#### 6.1 Create Importable Models Registry
Create `app/models/concerns/importable.rb` or registry class:
- Register all models that support import (Aircraft, Manufacturer, Operator, etc.)
- Each registration includes:
  - Model class
  - Available processor classes
  - Display name
  - Icon

#### 6.2 Processor Discovery
Create `Processors::Registry` module:
- Discover all processor classes dynamically or via explicit registration
- Provide metadata: name, description, model type, source URL
- Methods: `all_processors`, `processors_for_model(model)`, `find(class_name)`

---

### Phase 7: Testing & Documentation

#### 7.1 Tests
- Model tests for OperationJob, ScheduledOperation, AuditLog
- Policy tests for authorization
- Controller tests for admin namespace
- System tests for critical flows (trigger import, view results)
- Job tests (with stubbed processor calls)

#### 7.2 Seeds
- Add demo scheduled operations
- Add sample completed jobs for UI development

---

## File Structure Summary

```
app/
├── channels/
│   └── operation_job_channel.rb
├── controllers/
│   └── admin/
│       ├── base_controller.rb
│       ├── dashboard_controller.rb
│       ├── operation_jobs_controller.rb
│       ├── scheduled_operations_controller.rb
│       └── audit_logs_controller.rb
├── jobs/
│   ├── import_source_job.rb
│   ├── process_source_job.rb
│   └── scheduled_operation_runner_job.rb
├── models/
│   ├── operation_job.rb
│   ├── scheduled_operation.rb
│   ├── audit_log.rb
│   └── processors/
│       └── registry.rb
├── policies/
│   ├── application_policy.rb
│   ├── operation_job_policy.rb
│   ├── scheduled_operation_policy.rb
│   └── audit_log_policy.rb
├── views/
│   └── admin/
│       ├── dashboard/
│       │   └── index.html.erb
│       ├── operation_jobs/
│       │   ├── index.html.erb
│       │   ├── show.html.erb
│       │   └── _operation_job.html.erb
│       ├── scheduled_operations/
│       │   ├── index.html.erb
│       │   ├── _form.html.erb
│       │   └── _scheduled_operation.html.erb
│       └── audit_logs/
│           └── index.html.erb
└── javascript/
    └── controllers/
        ├── job_progress_controller.js
        ├── job_actions_controller.js
        └── cron_builder_controller.js

db/migrate/
├── XXXXXX_add_role_to_users.rb
├── XXXXXX_create_operation_jobs.rb
├── XXXXXX_create_scheduled_operations.rb
└── XXXXXX_create_audit_logs.rb

config/
├── solid_queue.yml
└── routes.rb (add admin namespace)
```

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Background Jobs | Solid Queue | Rails 8 native, no Redis dependency, built-in recurring jobs |
| Authorization | Custom policy classes | Lightweight, no gem overhead, fits simple 3-tier model |
| Real-time Updates | Turbo Streams + ActionCable | Already in stack, native Rails 8 integration |
| Audit Logging | Custom AuditLog model | Simple requirements, full control over schema |
| Cron Parsing | `fugit` gem | Lightweight, well-maintained cron parser |

---

## Dependencies to Add

```ruby
# Gemfile
gem "solid_queue"           # Background jobs with scheduling
gem "fugit"                 # Cron expression parsing
gem "mission_control-jobs"  # Optional: Web UI for Solid Queue monitoring
```

---

## Integration Points (Stubbed)

The following methods will be stubbed for later integration with the processor branch:

```ruby
# In ImportSourceJob
def perform_import(operation_job)
  # TODO: Replace with actual processor call
  # processor_class = operation_job.source_type.constantize
  # processor_class.import!
  
  # Stub: simulate import with delay
  sleep(2)
  { records_processed: rand(100..500), errors: [] }
end

# In ProcessSourceJob  
def perform_process(operation_job)
  # TODO: Replace with actual combiner call
  sleep(2)
  { records_processed: rand(50..200), errors: [] }
end
```
<!-- SECTION:PLAN:END -->
