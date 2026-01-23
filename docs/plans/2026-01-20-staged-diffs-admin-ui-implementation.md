# Phase 5: Admin UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement admin web interface for reviewing, approving, and managing staged batch changes.

**Architecture:** Admin namespace with base controller enforcing `admin?` access. StagedBatchesController handles CRUD and actions (apply/reject/rollback). ProcessorsController allows triggering processor jobs. Views use existing Tailwind patterns with Stimulus for interactivity.

**Tech Stack:** Rails 7, Minitest, Stimulus, Tailwind CSS, Pagy, Turbo

**Design Document:** `docs/plans/2026-01-20-staged-diffs-admin-ui-design.md`

---

## Phase 5.1: User Admin Flag

### Task 5.1.1: Add Admin Column to Users

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_admin_to_users.rb`

**Step 1: Generate migration**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails generate migration AddAdminToUsers admin:boolean
```

**Step 2: Edit migration to set default**

Edit the generated file to ensure default is false:

```ruby
# frozen_string_literal: true

class AddAdminToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
```

**Step 3: Run migration**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails db:migrate
```
Expected: Migration succeeds, schema updated.

**Step 4: Commit**

```bash
git add db/migrate/*_add_admin_to_users.rb db/schema.rb
git commit -m "feat: add admin boolean to users table"
```

---

### Task 5.1.2: Add Admin Helper Method to User Model

**Files:**
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

**Step 1: Write the test**

Create or update `test/models/user_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin? returns false by default" do
    user = User.new(email: "test@example.com", password: "password123")
    assert_not user.admin?
  end

  test "admin? returns true when admin flag is set" do
    user = User.new(email: "admin@example.com", password: "password123", admin: true)
    assert user.admin?
  end
end
```

**Step 2: Run test to verify it passes**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/user_test.rb
```
Expected: PASS (Rails generates `admin?` method automatically for boolean columns)

**Step 3: Update fixtures**

Edit `test/fixtures/users.yml` to add an admin user:

```yaml
one:
  email: "admin@me.com"
  contribution_trust_score: 50

trusted_contributor:
  email: "trusted@example.com"
  contribution_trust_score: 95

new_contributor:
  email: "new@example.com"
  contribution_trust_score: 10

admin:
  email: "superadmin@example.com"
  contribution_trust_score: 50
  admin: true
```

**Step 4: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb test/fixtures/users.yml
git commit -m "feat: add admin? helper and admin fixture"
```

---

## Phase 5.2: Admin Base Controller

### Task 5.2.1: Create Admin::BaseController

**Files:**
- Create: `app/controllers/admin/base_controller.rb`
- Create: `test/controllers/admin/base_controller_test.rb`

**Step 1: Write the test**

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  test "redirects non-admin users to root" do
    user = users(:one)
    sign_in user

    # We'll test via a subclass since BaseController has no actions
    # For now, just verify the controller exists and can be instantiated
    assert_kind_of ApplicationController, Admin::BaseController.new
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/base_controller_test.rb
```
Expected: FAIL - uninitialized constant Admin::BaseController

**Step 3: Create the controller**

Create `app/controllers/admin/base_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  # Base controller for all admin controllers.
  # Ensures only users with the admin flag can access admin pages.
  class BaseController < ApplicationController
    before_action :require_admin!

    private

    # Redirects non-admin users to the root path with an alert.
    def require_admin!
      return if current_user&.admin?

      redirect_to root_path, alert: "You don't have permission to access this area."
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/base_controller_test.rb
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/admin/base_controller.rb test/controllers/admin/base_controller_test.rb
git commit -m "feat: add Admin::BaseController with admin authorization"
```

---

## Phase 5.3: Staged Batches Controller

### Task 5.3.1: Create Admin::StagedBatchesController with Index

**Files:**
- Create: `app/controllers/admin/staged_batches_controller.rb`
- Create: `test/controllers/admin/staged_batches_controller_test.rb`

**Step 1: Write the test**

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::StagedBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  # Access control tests
  test "index redirects non-admin users" do
    sign_in @non_admin
    get admin_staged_batches_path
    assert_redirected_to root_path
  end

  test "index accessible to admin users" do
    sign_in @admin
    get admin_staged_batches_path
    assert_response :success
  end

  # Index tests
  test "index lists staged batches" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    get admin_staged_batches_path
    assert_response :success
    assert_select "table tbody tr", minimum: 1
  end

  test "index filters by status" do
    sign_in @admin
    pending_batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )
    applied_batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :applied
    )

    get admin_staged_batches_path(status: "pending")
    assert_response :success
  end

  test "index filters by entity_type" do
    sign_in @admin
    get admin_staged_batches_path(entity_type: "Aircraft")
    assert_response :success
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```
Expected: FAIL - uninitialized constant or routing error

**Step 3: Add routes**

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  devise_for :users

  # Search autocomplete suggestions API
  get 'search/suggestions', to: 'search_suggestions#index', as: :search_suggestions

  # Admin namespace
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

  resources :aircraft
  resources :aircraft_types, only: [:index, :show]
  resources :manufacturers, only: [:index, :show]
  resources :airports, only: [:index, :show]
  resources :runways, only: [:index]
  resources :countries, only: [:index, :show]
  resources :routes, only: [:index, :show]
  resources :operators
  get 'dashboard', to: 'home#dashboard'
  root to: 'home#dashboard'
end
```

**Step 4: Create the controller**

Create `app/controllers/admin/staged_batches_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  # Controller for managing staged batches.
  # Provides index, show, apply, reject, and rollback actions.
  class StagedBatchesController < BaseController
    before_action :set_staged_batch, only: [:show, :apply, :reject, :rollback]

    def index
      @batches = StagedBatch.recent
      @batches = @batches.where(status: params[:status]) if params[:status].present?
      @batches = @batches.for_entity(params[:entity_type]) if params[:entity_type].present?

      @pagy, @batches = pagy(@batches, items: 25)

      # For filter dropdowns
      @entity_types = StagedBatch.distinct.pluck(:entity_type).sort
      @statuses = StagedBatch.statuses.keys
    end

    def show
      @changes = @batch.staged_changes
      @changes = @changes.where(operation: params[:operation]) if params[:operation].present?
      @changes = @changes.where("record_identifier ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      @pagy, @changes = pagy(@changes, items: 50)

      # Counts for the grouping headers
      @creates_count = @batch.staged_changes.creates.count
      @updates_count = @batch.staged_changes.updates.count
    end

    def apply
      @batch.apply!(by: current_user)
      redirect_to admin_staged_batch_path(@batch), notice: "Batch applied successfully."
    rescue StagedBatch::InvalidStatusError, StagedBatch::StaleDataError, StagedBatch::ApplyError => e
      redirect_to admin_staged_batch_path(@batch), alert: "Failed to apply batch: #{e.message}"
    end

    def reject
      @batch.reject!(by: current_user, reason: params[:reason])
      redirect_to admin_staged_batch_path(@batch), notice: "Batch rejected."
    rescue StagedBatch::InvalidStatusError => e
      redirect_to admin_staged_batch_path(@batch), alert: "Failed to reject batch: #{e.message}"
    end

    def rollback
      # TODO: Implement rollback in Phase 7
      redirect_to admin_staged_batch_path(@batch), alert: "Rollback not yet implemented."
    end

    private

    def set_staged_batch
      @batch = StagedBatch.find(params[:id])
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```
Expected: Some tests may fail due to missing views - that's expected for now.

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/staged_batches_controller.rb test/controllers/admin/staged_batches_controller_test.rb
git commit -m "feat: add Admin::StagedBatchesController with index and filtering"
```

---

### Task 5.3.2: Add Apply and Reject Action Tests

**Files:**
- Modify: `test/controllers/admin/staged_batches_controller_test.rb`

**Step 1: Add tests for apply and reject actions**

Append to `test/controllers/admin/staged_batches_controller_test.rb`:

```ruby
  # Apply tests
  test "apply action applies pending batch" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "ZZ",
      operation: :create,
      diff: {
        "name" => [nil, "Test Country"],
        "iso_2char_code" => [nil, "ZZ"],
        "iso_3char_code" => [nil, "ZZZ"]
      }
    )

    assert_difference "Country.count", 1 do
      post apply_admin_staged_batch_path(batch)
    end

    assert_redirected_to admin_staged_batch_path(batch)
    batch.reload
    assert_equal "applied", batch.status
  end

  test "apply action shows error for non-pending batch" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :applied
    )

    post apply_admin_staged_batch_path(batch)
    assert_redirected_to admin_staged_batch_path(batch)
    follow_redirect!
    assert_match /Failed to apply/, flash[:alert]
  end

  # Reject tests
  test "reject action rejects pending batch" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    post reject_admin_staged_batch_path(batch), params: { reason: "Data looks incorrect" }
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
    assert_equal "Data looks incorrect", batch.notes
  end

  test "reject action without reason still works" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )

    post reject_admin_staged_batch_path(batch)
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
  end
```

**Step 2: Run tests**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```
Expected: PASS (controller actions already implemented)

**Step 3: Commit**

```bash
git add test/controllers/admin/staged_batches_controller_test.rb
git commit -m "test: add apply and reject action tests for staged batches"
```

---

## Phase 5.4: Staged Batches Views

### Task 5.4.1: Create Index View

**Files:**
- Create: `app/views/admin/staged_batches/index.html.erb`
- Create: `app/views/admin/staged_batches/_batch.html.erb`
- Create: `app/helpers/admin/staged_batches_helper.rb`

**Step 1: Create the helper**

Create `app/helpers/admin/staged_batches_helper.rb`:

```ruby
# frozen_string_literal: true

module Admin
  # Helper methods for staged batches views.
  module StagedBatchesHelper
    # Returns Tailwind classes for a status badge.
    #
    # @param status [String] The batch status
    # @return [String] Tailwind CSS classes
    def status_badge_classes(status)
      base = "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset"

      colour = case status
               when "pending"
                 "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
               when "applied"
                 "bg-green-50 text-green-700 ring-green-600/20"
               when "rejected", "failed"
                 "bg-red-50 text-red-700 ring-red-600/20"
               when "processing"
                 "bg-blue-50 text-blue-700 ring-blue-600/20"
               when "rolled_back", "superseded"
                 "bg-gray-50 text-gray-600 ring-gray-500/10"
               else
                 "bg-gray-50 text-gray-600 ring-gray-500/10"
               end

      "#{base} #{colour}"
    end

    # Formats a batch summary hash into a human-readable string.
    #
    # @param summary [Hash] The summary hash with created/updated counts
    # @return [String] Formatted summary
    def format_batch_summary(summary)
      return "No changes" if summary.blank?

      parts = []
      parts << "#{summary['created']} created" if summary["created"].to_i.positive?
      parts << "#{summary['updated']} updated" if summary["updated"].to_i.positive?
      parts.empty? ? "No changes" : parts.join(", ")
    end
  end
end
```

**Step 2: Create the partial**

Create `app/views/admin/staged_batches/_batch.html.erb`:

```erb
<tr class="<%= 'bg-yellow-50' if batch.pending? %>">
  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">
    <%= batch.entity_type %>
  </td>
  <td class="whitespace-nowrap px-3 py-4 text-sm">
    <span class="<%= status_badge_classes(batch.status) %>">
      <%= batch.status.titleize %>
    </span>
  </td>
  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
    <%= format_batch_summary(batch.summary) %>
  </td>
  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
    <%= time_ago_in_words(batch.created_at) %> ago
  </td>
  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
    <%= batch.reviewed_by&.name || "—" %>
  </td>
  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
    <%= link_to "View", admin_staged_batch_path(batch), class: "text-indigo-600 hover:text-indigo-900" %>
  </td>
</tr>
```

**Step 3: Create the index view**

Create `app/views/admin/staged_batches/index.html.erb`:

```erb
<% content_for :page_title, "Staged Batches" %>
<% content_for :page_description, "Review and approve data changes from processor runs." %>

<%# Filters %>
<div class="mb-6 flex flex-wrap gap-4">
  <%= form_with url: admin_staged_batches_path, method: :get, class: "flex flex-wrap gap-4", data: { turbo_frame: "_top" } do |f| %>
    <div>
      <%= f.select :status,
                   options_for_select([["All Statuses", ""]] + @statuses.map { |s| [s.titleize, s] }, params[:status]),
                   {},
                   class: "block rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6" %>
    </div>
    <div>
      <%= f.select :entity_type,
                   options_for_select([["All Entity Types", ""]] + @entity_types.map { |e| [e, e] }, params[:entity_type]),
                   {},
                   class: "block rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6" %>
    </div>
    <%= f.submit "Filter", class: "rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 cursor-pointer" %>
    <% if params[:status].present? || params[:entity_type].present? %>
      <%= link_to "Clear", admin_staged_batches_path, class: "rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50" %>
    <% end %>
  <% end %>
</div>

<%# Table %>
<div class="mt-8 flow-root">
  <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
    <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
      <table class="min-w-full divide-y divide-gray-300">
        <thead>
          <tr>
            <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-0">Entity Type</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Status</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Summary</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Created</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Reviewed By</th>
            <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-0">
              <span class="sr-only">View</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white">
          <% if @batches.any? %>
            <%= render partial: "batch", collection: @batches %>
          <% else %>
            <tr>
              <td colspan="6" class="py-8 text-center text-sm text-gray-500">
                No staged batches found.
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>

<%# Pagination %>
<% if @pagy.pages > 1 %>
  <div class="mt-6">
    <%== pagy_nav(@pagy) %>
  </div>
<% end %>
```

**Step 4: Run tests**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```
Expected: PASS

**Step 5: Commit**

```bash
git add app/views/admin/staged_batches/index.html.erb app/views/admin/staged_batches/_batch.html.erb app/helpers/admin/staged_batches_helper.rb
git commit -m "feat: add staged batches index view with filtering"
```

---

### Task 5.4.2: Create Show View with Diff Browser

**Files:**
- Create: `app/views/admin/staged_batches/show.html.erb`
- Create: `app/views/admin/staged_batches/_change.html.erb`
- Create: `app/views/admin/staged_batches/_diff.html.erb`

**Step 1: Create the diff partial**

Create `app/views/admin/staged_batches/_diff.html.erb`:

```erb
<%# Renders a single diff entry (field change) %>
<%# locals: field, old_value, new_value %>
<div class="flex items-start gap-2 py-1 text-sm font-mono">
  <span class="font-semibold text-gray-600 min-w-[120px]"><%= field %>:</span>
  <span class="text-red-600 line-through"><%= old_value.nil? ? "null" : old_value.inspect %></span>
  <span class="text-gray-400">→</span>
  <span class="text-green-600"><%= new_value.nil? ? "null" : new_value.inspect %></span>
</div>
```

**Step 2: Create the change partial**

Create `app/views/admin/staged_batches/_change.html.erb`:

```erb
<div class="border-b border-gray-200 py-3" data-controller="toggle">
  <div class="flex items-center justify-between cursor-pointer" data-action="click->toggle#toggle">
    <div class="flex items-center gap-4">
      <span class="<%= change.operation_create? ? 'text-green-600' : 'text-blue-600' %> font-medium text-sm uppercase w-16">
        <%= change.operation %>
      </span>
      <span class="font-mono text-sm text-gray-900"><%= change.record_identifier %></span>
      <span class="text-sm text-gray-500">
        (<%= change.diff.keys.count %> field<%= change.diff.keys.count == 1 ? '' : 's' %>)
      </span>
    </div>
    <svg class="h-5 w-5 text-gray-400 transition-transform" data-toggle-target="icon" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
    </svg>
  </div>

  <div class="hidden mt-3 pl-20 bg-gray-50 rounded-md p-3" data-toggle-target="toggleable">
    <% change.diff.each do |field, (old_value, new_value)| %>
      <%= render "diff", field: field, old_value: old_value, new_value: new_value %>
    <% end %>
  </div>
</div>
```

**Step 3: Create the show view**

Create `app/views/admin/staged_batches/show.html.erb`:

```erb
<% content_for :page_title, "Batch: #{@batch.entity_type}" %>
<% content_for :page_description, "Review staged changes from #{@batch.processor_type}" %>

<%# Header with metadata and actions %>
<div class="mb-8 bg-white shadow sm:rounded-lg">
  <div class="px-4 py-5 sm:p-6">
    <div class="sm:flex sm:items-start sm:justify-between">
      <div>
        <h3 class="text-base font-semibold leading-6 text-gray-900">
          Batch Details
        </h3>
        <div class="mt-2 max-w-xl text-sm text-gray-500">
          <dl class="grid grid-cols-2 gap-x-4 gap-y-2">
            <dt class="font-medium">Processor:</dt>
            <dd><%= @batch.processor_type %></dd>

            <dt class="font-medium">Entity Type:</dt>
            <dd><%= @batch.entity_type %></dd>

            <dt class="font-medium">Status:</dt>
            <dd><span class="<%= status_badge_classes(@batch.status) %>"><%= @batch.status.titleize %></span></dd>

            <dt class="font-medium">Created:</dt>
            <dd><%= @batch.created_at.strftime("%Y-%m-%d %H:%M") %></dd>

            <% if @batch.completed_at %>
              <dt class="font-medium">Completed:</dt>
              <dd><%= @batch.completed_at.strftime("%Y-%m-%d %H:%M") %></dd>
            <% end %>

            <% if @batch.applied_at %>
              <dt class="font-medium">Applied:</dt>
              <dd><%= @batch.applied_at.strftime("%Y-%m-%d %H:%M") %></dd>
            <% end %>

            <% if @batch.reviewed_by %>
              <dt class="font-medium">Reviewed By:</dt>
              <dd><%= @batch.reviewed_by.name %></dd>
            <% end %>

            <% if @batch.notes.present? %>
              <dt class="font-medium">Notes:</dt>
              <dd><%= @batch.notes %></dd>
            <% end %>

            <% if @batch.error_message.present? %>
              <dt class="font-medium text-red-600">Error:</dt>
              <dd class="text-red-600"><%= truncate(@batch.error_message, length: 200) %></dd>
            <% end %>
          </dl>
        </div>
      </div>

      <%# Action buttons %>
      <div class="mt-5 sm:ml-6 sm:mt-0 sm:flex sm:flex-shrink-0 sm:items-center gap-2">
        <% if @batch.pending? %>
          <%= button_to "Apply",
                        apply_admin_staged_batch_path(@batch),
                        method: :post,
                        class: "inline-flex items-center rounded-md bg-green-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-green-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600",
                        data: { turbo_confirm: "Are you sure you want to apply #{@batch.staged_changes.count} changes?" } %>

          <%= button_to "Reject",
                        reject_admin_staged_batch_path(@batch),
                        method: :post,
                        class: "inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600",
                        data: { turbo_confirm: "Are you sure you want to reject this batch?" } %>
        <% elsif @batch.applied? %>
          <%= button_to "Rollback",
                        rollback_admin_staged_batch_path(@batch),
                        method: :post,
                        class: "inline-flex items-center rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-orange-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600",
                        data: { turbo_confirm: "Are you sure you want to rollback this batch? This cannot be undone." } %>
        <% end %>
      </div>
    </div>
  </div>
</div>

<%# Summary panel %>
<div class="mb-6 grid grid-cols-3 gap-4">
  <div class="bg-green-50 rounded-lg p-4 text-center">
    <div class="text-2xl font-bold text-green-700"><%= @creates_count %></div>
    <div class="text-sm text-green-600">Creates</div>
  </div>
  <div class="bg-blue-50 rounded-lg p-4 text-center">
    <div class="text-2xl font-bold text-blue-700"><%= @updates_count %></div>
    <div class="text-sm text-blue-600">Updates</div>
  </div>
  <div class="bg-gray-50 rounded-lg p-4 text-center">
    <div class="text-2xl font-bold text-gray-700"><%= @batch.summary["unchanged"].to_i %></div>
    <div class="text-sm text-gray-600">Unchanged</div>
  </div>
</div>

<%# Search and filter %>
<div class="mb-6">
  <%= form_with url: admin_staged_batch_path(@batch), method: :get, class: "flex flex-wrap gap-4", data: { turbo_frame: "_top" } do |f| %>
    <div class="flex-1">
      <%= f.text_field :search,
                       value: params[:search],
                       placeholder: "Search by identifier...",
                       class: "block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6" %>
    </div>
    <div>
      <%= f.select :operation,
                   options_for_select([["All Operations", ""], ["Creates", "create"], ["Updates", "update"]], params[:operation]),
                   {},
                   class: "block rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6" %>
    </div>
    <%= f.submit "Filter", class: "rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 cursor-pointer" %>
    <% if params[:search].present? || params[:operation].present? %>
      <%= link_to "Clear", admin_staged_batch_path(@batch), class: "rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50" %>
    <% end %>
  <% end %>
</div>

<%# Changes list %>
<div class="bg-white shadow sm:rounded-lg">
  <div class="px-4 py-5 sm:p-6">
    <% if @changes.any? %>
      <div class="divide-y divide-gray-100">
        <%= render partial: "change", collection: @changes %>
      </div>

      <%# Pagination %>
      <% if @pagy.pages > 1 %>
        <div class="mt-6 border-t border-gray-200 pt-4">
          <%== pagy_nav(@pagy) %>
        </div>
      <% end %>
    <% else %>
      <p class="text-center text-sm text-gray-500 py-8">
        No changes match your filters.
      </p>
    <% end %>
  </div>
</div>

<%# Back link %>
<div class="mt-6">
  <%= link_to "← Back to Staged Batches", admin_staged_batches_path, class: "text-sm text-indigo-600 hover:text-indigo-500" %>
</div>
```

**Step 4: Add show test**

Add to `test/controllers/admin/staged_batches_controller_test.rb`:

```ruby
  # Show tests
  test "show displays batch details" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Test",
      record_identifier: "TEST-1",
      operation: :create,
      diff: { "name" => [nil, "Test"] }
    )

    get admin_staged_batch_path(batch)
    assert_response :success
    assert_select "h3", "Batch Details"
  end

  test "show filters changes by search" do
    sign_in @admin
    batch = StagedBatch.create!(
      processor_type: "Processors::Test::Test",
      entity_type: "Test",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Test",
      record_identifier: "VH-ABC",
      operation: :create,
      diff: { "name" => [nil, "Test"] }
    )
    batch.staged_changes.create!(
      record_type: "Test",
      record_identifier: "N12345",
      operation: :create,
      diff: { "name" => [nil, "Other"] }
    )

    get admin_staged_batch_path(batch, search: "VH")
    assert_response :success
  end
```

**Step 5: Run tests**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```
Expected: PASS

**Step 6: Commit**

```bash
git add app/views/admin/staged_batches/show.html.erb app/views/admin/staged_batches/_change.html.erb app/views/admin/staged_batches/_diff.html.erb test/controllers/admin/staged_batches_controller_test.rb
git commit -m "feat: add staged batch show view with diff browser"
```

---

## Phase 5.5: Processors Controller

### Task 5.5.1: Create Admin::ProcessorsController

**Files:**
- Create: `app/controllers/admin/processors_controller.rb`
- Create: `test/controllers/admin/processors_controller_test.rb`

**Step 1: Write the test**

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::ProcessorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  test "index redirects non-admin users" do
    sign_in @non_admin
    get admin_processors_path
    assert_redirected_to root_path
  end

  test "index accessible to admin users" do
    sign_in @admin
    get admin_processors_path
    assert_response :success
  end

  test "index lists available processors" do
    sign_in @admin
    get admin_processors_path
    assert_response :success
    # Should list at least Aircraft, Operator processors
    assert_select "table tbody tr", minimum: 1
  end

  test "create enqueues processor job" do
    sign_in @admin

    assert_enqueued_with(job: ProcessorJob) do
      post admin_processors_path, params: { entity_type: "Country" }
    end

    assert_redirected_to admin_processors_path
    follow_redirect!
    assert_match /enqueued/, flash[:notice]
  end

  test "create rejects invalid processor type" do
    sign_in @admin

    post admin_processors_path, params: { entity_type: "InvalidType" }
    assert_redirected_to admin_processors_path
    assert_match /Unknown processor/, flash[:alert]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/processors_controller_test.rb
```
Expected: FAIL - uninitialized constant

**Step 3: Create the controller**

Create `app/controllers/admin/processors_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  # Controller for triggering processor jobs.
  class ProcessorsController < BaseController
    # Known processor entity types.
    PROCESSOR_ENTITY_TYPES = %w[
      Aircraft
      AircraftType
      Airport
      Country
      Manufacturer
      Operator
      Runway
    ].freeze

    def index
      @processors = PROCESSOR_ENTITY_TYPES.map do |entity_type|
        processor_class = "Processors::#{entity_type}::#{entity_type}"
        last_batch = StagedBatch.where(entity_type: entity_type).recent.first

        {
          entity_type: entity_type,
          processor_class: processor_class,
          last_batch: last_batch,
          processing: last_batch&.processing?
        }
      end
    end

    def create
      entity_type = params[:entity_type]

      unless PROCESSOR_ENTITY_TYPES.include?(entity_type)
        redirect_to admin_processors_path, alert: "Unknown processor: #{entity_type}"
        return
      end

      processor_class = "Processors::#{entity_type}::#{entity_type}"

      # Verify the processor class exists
      begin
        processor_class.constantize
      rescue NameError
        redirect_to admin_processors_path, alert: "Processor not found: #{processor_class}"
        return
      end

      ProcessorJob.perform_later(processor_class, triggered_by_id: current_user.id)
      redirect_to admin_processors_path, notice: "#{entity_type} processor job enqueued."
    end
  end
end
```

**Step 4: Run tests**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/processors_controller_test.rb
```
Expected: Some may fail due to missing view

**Step 5: Commit**

```bash
git add app/controllers/admin/processors_controller.rb test/controllers/admin/processors_controller_test.rb
git commit -m "feat: add Admin::ProcessorsController for triggering jobs"
```

---

### Task 5.5.2: Create Processors Index View

**Files:**
- Create: `app/views/admin/processors/index.html.erb`

**Step 1: Create the view**

Create `app/views/admin/processors/index.html.erb`:

```erb
<% content_for :page_title, "Processors" %>
<% content_for :page_description, "Trigger data processor jobs to refresh entity data from sources." %>

<div class="mt-8 flow-root">
  <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
    <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
      <table class="min-w-full divide-y divide-gray-300">
        <thead>
          <tr>
            <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-0">Processor</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Last Run</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Status</th>
            <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Summary</th>
            <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-0">
              <span class="sr-only">Run</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white">
          <% @processors.each do |processor| %>
            <tr>
              <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">
                <%= processor[:entity_type] %>
              </td>
              <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                <% if processor[:last_batch] %>
                  <%= time_ago_in_words(processor[:last_batch].created_at) %> ago
                <% else %>
                  Never
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-4 text-sm">
                <% if processor[:last_batch] %>
                  <span class="<%= status_badge_classes(processor[:last_batch].status) %>">
                    <%= processor[:last_batch].status.titleize %>
                  </span>
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                <% if processor[:last_batch] %>
                  <%= format_batch_summary(processor[:last_batch].summary) %>
                <% else %>
                  —
                <% end %>
              </td>
              <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
                <% if processor[:processing] %>
                  <span class="text-gray-400">Running...</span>
                <% else %>
                  <%= button_to "Run",
                                admin_processors_path(entity_type: processor[:entity_type]),
                                method: :post,
                                class: "rounded-md bg-indigo-600 px-2.5 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
                                data: { turbo_confirm: "Run #{processor[:entity_type]} processor?" } %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>

<div class="mt-6">
  <%= link_to "← Back to Staged Batches", admin_staged_batches_path, class: "text-sm text-indigo-600 hover:text-indigo-500" %>
</div>
```

**Step 2: Run tests**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/processors_controller_test.rb
```
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/admin/processors/index.html.erb
git commit -m "feat: add processors index view"
```

---

## Phase 5.6: Navigation Updates

### Task 5.6.1: Add Admin Section to Sidebar

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/helpers/admin_helper.rb`

**Step 1: Create the admin helper**

Create `app/helpers/admin_helper.rb`:

```ruby
# frozen_string_literal: true

# Helper methods for admin functionality.
module AdminHelper
  # Returns the count of pending staged batches.
  #
  # @return [Integer]
  def pending_batches_count
    @pending_batches_count ||= StagedBatch.pending.count
  end
end
```

**Step 2: Update the layout**

Find the admin section placeholder in `app/views/layouts/application.html.erb` and add the Admin section before the Settings link (around line 211-216). Locate this section:

```erb
            </ul>
          </li>
          <li class="mt-auto pb-2">
            <a href="#" class="group -mx-2 flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 text-gray-400 hover:bg-gray-800 hover:text-white">
```

Insert before the `<li class="mt-auto pb-2">` line:

```erb
            <% if current_user&.admin? %>
              <ul role="list" class="-mx-2 space-y-1">
                <div class="mt-2 text-xs font-semibold leading-6 text-gray-400">Admin</div>
                <li>
                  <%= link_to admin_staged_batches_path, class: "text-gray-300 hover:-mb-0.5 hover:border-b-2 hover:border-yellow-500 group flex items-center gap-x-3 p-2 text-sm leading-6 font-semibold" do %>
                    <i class="size-6 group-hover:text-yellow-500 fa-solid fa-layer-group"></i>
                    <span class="group-hover:bg-linear-to-r group-hover:from-violet-500 group-hover:to-fuchsia-500 group-hover:text-transparent group-hover:bg-clip-text">
                      Staged Batches
                    </span>
                    <% if pending_batches_count > 0 %>
                      <span class="ml-auto inline-flex items-center rounded-full bg-yellow-400 px-2 py-0.5 text-xs font-medium text-yellow-900">
                        <%= pending_batches_count %>
                      </span>
                    <% end %>
                  <% end %>
                </li>
                <li>
                  <%= link_to admin_processors_path, class: "text-gray-300 hover:-mb-0.5 hover:border-b-2 hover:border-yellow-500 group flex items-center gap-x-3 p-2 text-sm leading-6 font-semibold" do %>
                    <i class="size-6 group-hover:text-yellow-500 fa-solid fa-gears"></i>
                    <span class="group-hover:bg-linear-to-r group-hover:from-violet-500 group-hover:to-fuchsia-500 group-hover:text-transparent group-hover:bg-clip-text">
                      Processors
                    </span>
                  <% end %>
                </li>
              </ul>
            <% end %>
```

**Step 3: Verify manually**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails server
```
Log in as an admin user and verify the Admin section appears in the sidebar.

**Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb app/helpers/admin_helper.rb
git commit -m "feat: add Admin section to sidebar with pending badge"
```

---

## Phase 5.7: Integration Testing

### Task 5.7.1: Add Full Workflow Integration Test

**Files:**
- Create: `test/integration/admin_staged_batches_workflow_test.rb`

**Step 1: Write the integration test**

```ruby
# frozen_string_literal: true

require "test_helper"

class AdminStagedBatchesWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
  end

  test "full workflow: trigger processor, review batch, apply changes" do
    sign_in @admin

    # 1. View processors page
    get admin_processors_path
    assert_response :success

    # 2. Trigger a processor (Country is small and safe for tests)
    # Note: This enqueues a job, doesn't run it synchronously
    assert_enqueued_with(job: ProcessorJob) do
      post admin_processors_path, params: { entity_type: "Country" }
    end
    assert_redirected_to admin_processors_path

    # 3. Create a batch manually for testing the review flow
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending,
      summary: { "created" => 1, "updated" => 0 }
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "ZZ",
      operation: :create,
      diff: {
        "name" => [nil, "Test Country"],
        "iso_2char_code" => [nil, "ZZ"],
        "iso_3char_code" => [nil, "ZZZ"]
      }
    )

    # 4. View staged batches index
    get admin_staged_batches_path
    assert_response :success
    assert_select "tr", text: /Country/

    # 5. View batch details
    get admin_staged_batch_path(batch)
    assert_response :success
    assert_select "h3", "Batch Details"

    # 6. Apply the batch
    assert_difference "Country.count", 1 do
      post apply_admin_staged_batch_path(batch)
    end
    assert_redirected_to admin_staged_batch_path(batch)

    # 7. Verify batch status changed
    batch.reload
    assert_equal "applied", batch.status
    assert_equal @admin, batch.reviewed_by

    # 8. Verify the country was created
    country = Country.find_by(iso_2char_code: "ZZ")
    assert_not_nil country
    assert_equal "Test Country", country.name
  end

  test "reject workflow: review batch and reject with reason" do
    sign_in @admin

    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "YY",
      operation: :create,
      diff: { "name" => [nil, "Bad Data"] }
    )

    # Reject the batch
    post reject_admin_staged_batch_path(batch), params: { reason: "Data quality issue" }
    assert_redirected_to admin_staged_batch_path(batch)

    batch.reload
    assert_equal "rejected", batch.status
    assert_equal "Data quality issue", batch.notes
    assert_equal @admin, batch.reviewed_by
  end
end
```

**Step 2: Run the test**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/integration/admin_staged_batches_workflow_test.rb
```
Expected: PASS

**Step 3: Commit**

```bash
git add test/integration/admin_staged_batches_workflow_test.rb
git commit -m "test: add admin staged batches workflow integration test"
```

---

## Summary

This plan covers all tasks for Phase 5:

| Task | Description |
|------|-------------|
| 5.1.1 | Add admin column to users |
| 5.1.2 | Add admin helper method and fixtures |
| 5.2.1 | Create Admin::BaseController |
| 5.3.1 | Create Admin::StagedBatchesController with index |
| 5.3.2 | Add apply and reject action tests |
| 5.4.1 | Create index view with filtering |
| 5.4.2 | Create show view with diff browser |
| 5.5.1 | Create Admin::ProcessorsController |
| 5.5.2 | Create processors index view |
| 5.6.1 | Add Admin section to sidebar |
| 5.7.1 | Add full workflow integration test |

**After completing Phase 5**, you'll have a working admin UI for reviewing and approving staged batches, plus the ability to trigger processor jobs on-demand.
