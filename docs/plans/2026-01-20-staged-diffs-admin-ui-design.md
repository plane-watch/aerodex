# Staged Diffs Admin UI Design

**Status:** Draft
**Date:** 2026-01-20
**Author:** Tim (with Claude)
**Parent:** `docs/plans/2026-01-18-staged-diffs-design.md` (Phase 5)

## Overview

Admin web interface for reviewing, approving, and managing staged batch changes. Provides visibility into processor runs and allows admins to trigger processors on-demand.

## Access Control

- **Admin-only access** via `admin` boolean on User model
- Migration adds `admin` column (boolean, default: false)
- `Admin::BaseController` enforces access with `before_action :require_admin!`

## Routes

```ruby
namespace :admin do
  resources :staged_batches, only: [:index, :show] do
    member do
      post :apply
      post :reject
      post :rollback
    end
  end

  resources :processors, only: [:index, :create]
end
```

## Controllers

### Admin::BaseController

Base controller for all admin controllers. Inherits from `ApplicationController`.

```ruby
class Admin::BaseController < ApplicationController
  before_action :require_admin!

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "You don't have permission to access this area."
    end
  end
end
```

### Admin::StagedBatchesController

| Action | Purpose |
|--------|---------|
| `index` | List batches with filtering by status and entity type |
| `show` | Display batch details with diff browser |
| `apply` | Apply a pending batch (POST) |
| `reject` | Reject a pending batch with optional notes (POST) |
| `rollback` | Rollback an applied batch (POST) |

### Admin::ProcessorsController

| Action | Purpose |
|--------|---------|
| `index` | List available processors with run status |
| `create` | Trigger a processor job (POST with `processor_type` param) |

---

## Views

### Staged Batches Index (`/admin/staged_batches`)

**Filters:**
- Status dropdown: All, Pending, Applied, Rejected, Failed, Processing, Superseded, Rolled Back
- Entity type dropdown: All, plus dynamically populated from existing batches

**Table columns:**

| Column | Description |
|--------|-------------|
| Entity Type | e.g. "Aircraft", "Operator" |
| Status | Coloured badge (pending=yellow, applied=green, rejected/failed=red) |
| Summary | "12 created, 5 updated" |
| Created | Relative timestamp |
| Reviewed By | User name or "—" |
| Actions | "View" link |

**Behaviour:**
- Pending batches sorted to top with subtle highlight
- Pagination via Pagy
- "Run Processor" button in page actions (dropdown to select processor)

---

### Staged Batch Show (`/admin/staged_batches/:id`)

#### Header Section

**Metadata:**
- Processor type
- Entity type
- Status badge
- Timestamps: created, completed, applied/reviewed

**Summary panel:**
- "423 created, 87 updated, 12,045 unchanged"

**Action buttons** (conditional):

| Status | Available Actions |
|--------|-------------------|
| Pending | Apply (green), Reject (red, opens notes modal) |
| Applied | Rollback (orange, with confirmation) |
| Other | None (read-only) |

#### Diff Browser Section

**Search/filter bar:**
- Text input: searches by `record_identifier`
- Operation filter: All / Creates only / Updates only

**Grouped display:**

Two collapsible sections showing counts:
- "Creates (423)"
- "Updates (87)"

**Change row format:**

| Identifier | Fields Changed | |
|------------|----------------|---|
| VH-ABC | registration, owner, operator_id | ▼ (expand) |

**Expanded row (diff detail):**

```
registration: null → "VH-ABC"
owner: null → "Qantas Airways"
operator_id: null → 142
```

For updates, displays old → new values.

**Pagination:** Within each group, paginate changes (e.g. 50 per page).

---

### Processors Index (`/admin/processors`)

Lists all available processors with their recent run status.

**Table columns:**

| Column | Description |
|--------|-------------|
| Processor | Entity type name (e.g. "Aircraft") |
| Last Run | Timestamp of most recent batch |
| Status | Status of most recent batch (badge) |
| Actions | "Run" button |

**Run button behaviour:**
- Triggers `ProcessorJob.perform_later("Processors::#{entity}::#{entity}")`
- Redirects back with flash: "Aircraft processor job enqueued"
- Disabled if a batch for that entity is currently `processing`

---

## Navigation Changes

Add "Admin" section to sidebar (above Settings, visible only to admins):

```
Admin
├── Staged Batches    [3]  ← pending count badge
└── Processors
```

**Pending badge:**
- Shows count of batches in `pending` status
- Hidden when count is zero
- Small pill/badge style consistent with app design

**Visibility:**
- Entire Admin section hidden for non-admin users
- Check `current_user&.admin?` in layout

---

## Implementation Tasks

### Database
- [ ] Add `admin` boolean to users table (migration)

### Controllers
- [ ] Create `Admin::BaseController` with admin authorisation
- [ ] Create `Admin::StagedBatchesController` (index, show, apply, reject, rollback)
- [ ] Create `Admin::ProcessorsController` (index, create)

### Views
- [ ] Create `admin/staged_batches/index.html.erb` with filters
- [ ] Create `admin/staged_batches/show.html.erb` with diff browser
- [ ] Create `admin/processors/index.html.erb`
- [ ] Create partials for batch row, change row, diff display

### Layout
- [ ] Add Admin section to sidebar navigation
- [ ] Add pending batch count badge
- [ ] Conditionally show Admin section for admin users only

### JavaScript (Stimulus)
- [ ] Collapsible sections for creates/updates groups
- [ ] Search/filter within diff browser (client-side or server-side TBD)
- [ ] Confirmation modal for apply/reject/rollback actions

---

## Open Questions

1. **Client-side vs server-side filtering:** For the diff browser search, should filtering happen client-side (faster for small batches) or server-side (necessary for large batches)? Recommend server-side with Turbo Frames for consistency.

2. **Reject notes:** Required or optional? Current design has optional notes.

3. **Rollback confirmation:** Simple browser confirm, or modal with warning text? Recommend modal given the destructive nature.
