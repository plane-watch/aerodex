# Staged Diffs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a staging layer for batch processor changes with review/approve workflow, ActiveJob execution, and admin UI.

**Architecture:** Two new tables (`staged_batches`, `staged_changes`) capture diffs before applying. Processors write to staging instead of directly to canonical tables. ActiveJob runs processors in background. Admins review and approve batches via web UI or rake tasks.

**Tech Stack:** Rails 7, PostgreSQL, ActiveJob, Minitest

**Design Document:** `docs/plans/2026-01-18-staged-diffs-design.md`

---

## Phase 1: Core Infrastructure

### Task 1.1: Create StagedBatch Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_staged_batches.rb`

**Step 1: Generate migration**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails generate migration CreateStagedBatches
```

**Step 2: Write migration content**

Edit the generated migration file:

```ruby
# frozen_string_literal: true

class CreateStagedBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :staged_batches, id: :uuid do |t|
      t.string :processor_type, null: false
      t.string :entity_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :summary, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :job_id
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :applied_at
      t.datetime :reviewed_at
      t.text :notes
      t.text :error_message

      t.timestamps
    end

    add_index :staged_batches, :status
    add_index :staged_batches, :entity_type
    add_index :staged_batches, :job_id
    add_index :staged_batches, :created_at
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
git add db/migrate/*_create_staged_batches.rb db/schema.rb
git commit -m "feat: add staged_batches migration

Creates the staged_batches table for tracking processor batch runs
with job tracking, review workflow, and audit fields."
```

---

### Task 1.2: Create StagedChange Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_staged_changes.rb`

**Step 1: Generate migration**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails generate migration CreateStagedChanges
```

**Step 2: Write migration content**

```ruby
# frozen_string_literal: true

class CreateStagedChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :staged_changes do |t|
      t.references :staged_batch, null: false, foreign_key: true, type: :uuid
      t.string :record_type, null: false
      t.bigint :record_id
      t.string :record_identifier, null: false
      t.integer :operation, null: false
      t.jsonb :diff, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :staged_changes, [:record_type, :record_id]
    add_index :staged_changes, :record_identifier
  end
end
```

**Step 3: Run migration**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails db:migrate
```
Expected: Migration succeeds.

**Step 4: Commit**

```bash
git add db/migrate/*_create_staged_changes.rb db/schema.rb
git commit -m "feat: add staged_changes migration

Creates the staged_changes table for storing individual record diffs
within a batch, with polymorphic record references."
```

---

### Task 1.3: Create StagedBatch Model

**Files:**
- Create: `app/models/staged_batch.rb`
- Create: `test/models/staged_batch_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class StagedBatchTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    batch = StagedBatch.new(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft"
    )
    assert batch.valid?
  end

  test "invalid without processor_type" do
    batch = StagedBatch.new(entity_type: "Aircraft")
    assert_not batch.valid?
    assert_includes batch.errors[:processor_type], "can't be blank"
  end

  test "invalid without entity_type" do
    batch = StagedBatch.new(processor_type: "Processors::Aircraft::Aircraft")
    assert_not batch.valid?
    assert_includes batch.errors[:entity_type], "can't be blank"
  end

  test "default status is processing" do
    batch = StagedBatch.new
    assert_equal "processing", batch.status
  end

  test "pending scope returns only pending batches" do
    processing = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :processing
    )
    pending = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :pending
    )
    applied = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :applied
    )

    results = StagedBatch.pending
    assert_includes results, pending
    assert_not_includes results, processing
    assert_not_includes results, applied
  end

  test "for_entity scope filters by entity type" do
    aircraft_batch = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft"
    )
    operator_batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator"
    )

    results = StagedBatch.for_entity("Aircraft")
    assert_includes results, aircraft_batch
    assert_not_includes results, operator_batch
  end

  test "summary defaults to empty hash" do
    batch = StagedBatch.new
    assert_equal({}, batch.summary)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_batch_test.rb
```
Expected: FAIL - uninitialized constant StagedBatch

**Step 3: Write the model**

```ruby
# frozen_string_literal: true

# Represents a batch of staged changes from a processor run.
#
# A StagedBatch captures all the changes a processor would make, allowing
# review and approval before applying them to the database.
#
# == Statuses
# - processing: Job is currently running
# - pending: Processing complete, awaiting review
# - approved: Reviewed and approved (transitional)
# - applied: Changes have been committed to the database
# - rejected: Batch was rejected, changes discarded
# - superseded: A newer batch replaced this one
# - rolled_back: Applied changes were reversed
# - failed: Processing encountered an error
#
class StagedBatch < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :staged_changes, dependent: :destroy

  # Enums
  enum :status, {
    processing: 0,
    pending: 1,
    approved: 2,
    applied: 3,
    rejected: 4,
    superseded: 5,
    rolled_back: 6,
    failed: 7
  }

  # Validations
  validates :processor_type, presence: true
  validates :entity_type, presence: true

  # Scopes
  scope :for_entity, ->(type) { where(entity_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :actionable, -> { where(status: [:pending, :applied]) }
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_batch_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb
git commit -m "feat: add StagedBatch model with validations and scopes"
```

---

### Task 1.4: Create StagedChange Model

**Files:**
- Create: `app/models/staged_change.rb`
- Create: `test/models/staged_change_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class StagedChangeTest < ActiveSupport::TestCase
  setup do
    @batch = StagedBatch.create!(
      processor_type: "Processors::Aircraft::Aircraft",
      entity_type: "Aircraft",
      status: :processing
    )
  end

  test "valid with required attributes" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create,
      diff: { "registration" => [nil, "VH-ABC"] }
    )
    assert change.valid?
  end

  test "invalid without staged_batch" do
    change = StagedChange.new(
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:staged_batch], "must exist"
  end

  test "invalid without record_type" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_identifier: "7C1469",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:record_type], "can't be blank"
  end

  test "invalid without record_identifier" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      operation: :create
    )
    assert_not change.valid?
    assert_includes change.errors[:record_identifier], "can't be blank"
  end

  test "record_id is optional for creates" do
    change = StagedChange.new(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create,
      record_id: nil
    )
    assert change.valid?
  end

  test "diff defaults to empty hash" do
    change = StagedChange.new
    assert_equal({}, change.diff)
  end

  test "creates scope returns only create operations" do
    create_change = StagedChange.create!(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1469",
      operation: :create
    )
    update_change = StagedChange.create!(
      staged_batch: @batch,
      record_type: "Aircraft",
      record_identifier: "7C1470",
      record_id: 123,
      operation: :update
    )

    results = StagedChange.creates
    assert_includes results, create_change
    assert_not_includes results, update_change
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_change_test.rb
```
Expected: FAIL - uninitialized constant StagedChange

**Step 3: Write the model**

```ruby
# frozen_string_literal: true

# Represents an individual record change within a StagedBatch.
#
# Each StagedChange captures the diff for a single record, including:
# - The record type and ID (polymorphic reference)
# - A human-readable identifier (e.g., ICAO code for aircraft)
# - The operation type (create or update)
# - The diff as a hash of field_name => [old_value, new_value]
#
class StagedChange < ApplicationRecord
  # Associations
  belongs_to :staged_batch

  # Enums
  enum :operation, {
    create: 0,
    update: 1
  }

  # Validations
  validates :record_type, presence: true
  validates :record_identifier, presence: true
  validates :operation, presence: true

  # Scopes
  scope :creates, -> { where(operation: :create) }
  scope :updates, -> { where(operation: :update) }
  scope :for_record, ->(type, id) { where(record_type: type, record_id: id) }

  # Returns the target model class.
  #
  # @return [Class] The ActiveRecord model class
  def record_class
    record_type.constantize
  end

  # Returns the existing record if this is an update.
  #
  # @return [ApplicationRecord, nil] The record or nil for creates
  def record
    return nil if record_id.blank?

    record_class.find_by(id: record_id)
  end

  # Returns the new values from the diff.
  #
  # @return [Hash] Field names mapped to new values
  def new_values
    diff.transform_values(&:last)
  end

  # Returns the old values from the diff.
  #
  # @return [Hash] Field names mapped to old values
  def old_values
    diff.transform_values(&:first)
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_change_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/staged_change.rb test/models/staged_change_test.rb
git commit -m "feat: add StagedChange model with validations and helpers"
```

---

### Task 1.5: Add StagedBatch#apply! Method

**Files:**
- Modify: `app/models/staged_batch.rb`
- Modify: `test/models/staged_batch_test.rb`

**Step 1: Add tests for apply!**

Append to `test/models/staged_batch_test.rb`:

```ruby
  test "apply! raises error if not pending" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :processing
    )

    assert_raises(StagedBatch::InvalidStatusError) do
      batch.apply!(by: nil)
    end
  end

  test "apply! transitions status to applied" do
    batch = StagedBatch.create!(
      processor_type: "Processors::Operator::Operator",
      entity_type: "Operator",
      status: :pending
    )

    batch.apply!(by: nil)

    assert_equal "applied", batch.status
    assert_not_nil batch.applied_at
  end

  test "apply! creates records for create operations" do
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
      batch.apply!(by: nil)
    end

    country = Country.find_by(iso_2char_code: "ZZ")
    assert_equal "Test Country", country.name
  end

  test "apply! updates records for update operations" do
    country = Country.create!(
      name: "Old Name",
      iso_2char_code: "YY",
      iso_3char_code: "YYY"
    )
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "YY",
      record_id: country.id,
      operation: :update,
      diff: { "name" => ["Old Name", "New Name"] }
    )

    batch.apply!(by: nil)

    country.reload
    assert_equal "New Name", country.name
  end

  test "apply! raises StaleDataError if record modified since batch created" do
    country = Country.create!(
      name: "Original",
      iso_2char_code: "XX",
      iso_3char_code: "XXX"
    )
    batch = StagedBatch.create!(
      processor_type: "Processors::Country::Country",
      entity_type: "Country",
      status: :pending,
      created_at: 1.hour.ago
    )
    batch.staged_changes.create!(
      record_type: "Country",
      record_identifier: "XX",
      record_id: country.id,
      operation: :update,
      diff: { "name" => ["Original", "Staged Change"] }
    )

    # Modify the record after batch was created
    country.update!(name: "External Change")

    assert_raises(StagedBatch::StaleDataError) do
      batch.apply!(by: nil)
    end
  end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_batch_test.rb
```
Expected: FAIL - undefined method `apply!`, undefined constant errors

**Step 3: Implement apply! method**

Add to `app/models/staged_batch.rb` after the scopes:

```ruby
  # Custom errors
  class InvalidStatusError < StandardError; end
  class StaleDataError < StandardError; end
  class ApplyError < StandardError; end

  # Applies all staged changes to the database.
  #
  # @param by [User, nil] The user approving the batch
  # @raise [InvalidStatusError] If batch is not pending
  # @raise [StaleDataError] If any target record was modified after staging
  # @raise [ApplyError] If apply fails
  def apply!(by:)
    raise InvalidStatusError, "Batch must be pending to apply (current: #{status})" unless pending?

    transaction do
      check_for_stale_data!
      apply_changes!
      update!(
        status: :applied,
        applied_at: Time.current,
        reviewed_by: by,
        reviewed_at: Time.current
      )
    end

    run_post_apply_hooks
  end

  # Rejects the batch, discarding all staged changes.
  #
  # @param by [User, nil] The user rejecting the batch
  # @param reason [String, nil] Optional rejection reason
  def reject!(by:, reason: nil)
    raise InvalidStatusError, "Batch must be pending to reject (current: #{status})" unless pending?

    update!(
      status: :rejected,
      reviewed_by: by,
      reviewed_at: Time.current,
      notes: reason
    )
  end

  private

  # Checks if any target records have been modified since the batch was created.
  #
  # @raise [StaleDataError] If stale data is detected
  def check_for_stale_data!
    staged_changes.updates.find_each do |change|
      record = change.record
      next unless record

      if record.updated_at > created_at
        raise StaleDataError, "Record #{change.record_type}##{change.record_id} " \
                              "was modified after batch was created"
      end
    end
  end

  # Applies all staged changes to the database.
  def apply_changes!
    # Group changes by record type for efficient bulk operations
    changes_by_type = staged_changes.group_by(&:record_type)

    changes_by_type.each do |record_type, changes|
      model_class = record_type.constantize

      creates = changes.select(&:create?)
      updates = changes.select(&:update?)

      apply_creates(model_class, creates) if creates.any?
      apply_updates(model_class, updates) if updates.any?
    end
  end

  # Applies create operations using insert_all.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The create changes
  def apply_creates(model_class, changes)
    now = Time.current
    records = changes.map do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:created_at] ||= now
      attrs[:updated_at] ||= now
      attrs
    end

    model_class.insert_all(records)
  end

  # Applies update operations using upsert_all.
  #
  # @param model_class [Class] The model class
  # @param changes [Array<StagedChange>] The update changes
  def apply_updates(model_class, changes)
    now = Time.current
    records = changes.map do |change|
      attrs = change.new_values.symbolize_keys
      attrs[:id] = change.record_id
      attrs[:updated_at] = now
      attrs
    end

    model_class.upsert_all(records, unique_by: :id)
  end

  # Runs post-apply hooks like reindexing.
  def run_post_apply_hooks
    # Reindex affected models for search
    entity_type.constantize.reindex! if entity_type.constantize.respond_to?(:reindex!)
  rescue NameError
    # Entity type may not be a direct model class
    Rails.logger.warn "Could not reindex #{entity_type} - not a model class"
  end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/staged_batch_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/staged_batch.rb test/models/staged_batch_test.rb
git commit -m "feat: add StagedBatch#apply! and #reject! methods

Implements atomic batch apply with:
- Status validation
- Stale data detection
- Bulk insert/upsert operations
- Post-apply reindexing"
```

---

## Phase 2: ActiveJob Setup

### Task 2.1: Create ProcessorJob Base Class

**Files:**
- Create: `app/jobs/processor_job.rb`
- Create: `test/jobs/processor_job_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessorJobTest < ActiveJob::TestCase
  # We test this with a mock processor since real processors
  # require database fixtures

  class MockProcessor
    def self.combine_sources(triggered_by: nil)
      StagedBatch.create!(
        processor_type: name,
        entity_type: "Mock",
        status: :pending
      )
    end
  end

  test "perform creates a staged batch" do
    # Register the mock processor
    stub_const("Processors::Mock::Mock", MockProcessor)

    assert_difference "StagedBatch.count", 1 do
      ProcessorJob.perform_now("Processors::Mock::Mock")
    end
  end

  test "perform sets job_id on the batch" do
    stub_const("Processors::Mock::Mock", MockProcessor)

    job = ProcessorJob.new("Processors::Mock::Mock")
    job.perform_now

    batch = StagedBatch.last
    assert_equal job.job_id, batch.job_id
  end

  private

  def stub_const(name, value)
    parts = name.split("::")
    parent = parts[0..-2].inject(Object) { |mod, part| mod.const_get(part) rescue mod.const_set(part, Module.new) }
    parent.const_set(parts.last, value) unless parent.const_defined?(parts.last)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/jobs/processor_job_test.rb
```
Expected: FAIL - uninitialized constant ProcessorJob

**Step 3: Write the job class**

```ruby
# frozen_string_literal: true

# Base job for running data processors.
#
# Processors are run in the background and create StagedBatch records
# that must be reviewed and approved before changes are applied.
#
# @example Enqueue a processor
#   ProcessorJob.perform_later("Processors::Aircraft::Aircraft")
#
# @example Run synchronously
#   ProcessorJob.perform_now("Processors::Aircraft::Aircraft")
#
class ProcessorJob < ApplicationJob
  queue_as :processors

  # Called before perform to set up tracking.
  before_perform do |job|
    @job_id = job.job_id
  end

  # Runs the specified processor.
  #
  # @param processor_class_name [String] The fully-qualified processor class name
  # @param triggered_by_id [Integer, nil] The ID of the user who triggered the run
  def perform(processor_class_name, triggered_by_id: nil)
    processor_class = processor_class_name.constantize
    triggered_by = triggered_by_id ? User.find(triggered_by_id) : nil

    batch = processor_class.combine_sources(triggered_by: triggered_by)

    # Update the batch with job tracking info
    batch.update!(job_id: @job_id) if batch.is_a?(StagedBatch)
  rescue StandardError => e
    # If we have a batch, mark it as failed
    if defined?(batch) && batch.is_a?(StagedBatch)
      batch.update!(
        status: :failed,
        error_message: "#{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      )
    end
    raise
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/jobs/processor_job_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/jobs/processor_job.rb test/jobs/processor_job_test.rb
git commit -m "feat: add ProcessorJob base class for background processing

Runs processors via ActiveJob with:
- Job ID tracking on batches
- Error handling and batch failure status
- Support for triggered_by user tracking"
```

---

## Phase 3: Processor Integration

### Task 3.1: Add Staging Methods to Processors::Base

**Files:**
- Modify: `app/models/processors/base.rb`
- Create: `test/processor/base_staging_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessorBaseStagingTest < ActiveSupport::TestCase
  # Test processor that uses staging
  class TestProcessor < Processors::Base
    def self.combine_sources(triggered_by: nil)
      with_staged_batch(entity_type: "Country", triggered_by: triggered_by) do
        # Simulate processing a country
        country = Country.new(
          name: "Test Country",
          iso_2char_code: "TC",
          iso_3char_code: "TST"
        )

        stage_change(
          country,
          operation: :create,
          identifier: "TC"
        )
      end
    end
  end

  test "with_staged_batch creates a batch record" do
    assert_difference "StagedBatch.count", 1 do
      TestProcessor.combine_sources
    end
  end

  test "with_staged_batch sets processor_type" do
    batch = TestProcessor.combine_sources
    assert_equal "ProcessorBaseStagingTest::TestProcessor", batch.processor_type
  end

  test "with_staged_batch sets entity_type" do
    batch = TestProcessor.combine_sources
    assert_equal "Country", batch.entity_type
  end

  test "with_staged_batch starts in processing status" do
    # We need to check during the block, so use a flag
    status_during_block = nil

    Processors::Base.class_eval do
      define_singleton_method(:test_with_staged_batch) do
        with_staged_batch(entity_type: "Test", triggered_by: nil) do
          status_during_block = @current_batch.status
        end
      end
    end

    Processors::Base.test_with_staged_batch
    assert_equal "processing", status_during_block
  end

  test "with_staged_batch transitions to pending on success" do
    batch = TestProcessor.combine_sources
    assert_equal "pending", batch.status
  end

  test "stage_change creates a StagedChange record" do
    assert_difference "StagedChange.count", 1 do
      TestProcessor.combine_sources
    end
  end

  test "stage_change captures diff for new records" do
    batch = TestProcessor.combine_sources
    change = batch.staged_changes.first

    assert_equal "create", change.operation
    assert_equal "TC", change.record_identifier
    assert_includes change.diff.keys, "name"
    assert_equal [nil, "Test Country"], change.diff["name"]
  end

  test "summary is updated with counts" do
    batch = TestProcessor.combine_sources
    assert_equal 1, batch.summary["created"]
    assert_equal 0, batch.summary["updated"]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/processor/base_staging_test.rb
```
Expected: FAIL - undefined method `with_staged_batch`

**Step 3: Add staging methods to Processors::Base**

Add to `app/models/processors/base.rb` after the existing class methods:

```ruby
    # Thread-local storage for the current batch during processing
    def self.current_batch
      Thread.current[:processor_current_batch]
    end

    def self.current_batch=(batch)
      Thread.current[:processor_current_batch] = batch
    end

    # Wraps a processor run with staged batch tracking.
    #
    # Creates a StagedBatch at the start, yields to the processing block,
    # and finalises the batch status and summary on completion.
    #
    # @param entity_type [String] The entity type being processed (e.g., "Aircraft")
    # @param triggered_by [User, nil] The user who triggered the run
    # @yield The processing block
    # @return [StagedBatch] The completed batch
    def self.with_staged_batch(entity_type:, triggered_by: nil)
      check_pending_batch!(entity_type)

      self.current_batch = StagedBatch.create!(
        processor_type: name,
        entity_type: entity_type,
        status: :processing,
        created_by: triggered_by,
        started_at: Time.current,
        summary: { "created" => 0, "updated" => 0, "unchanged" => 0 }
      )

      yield

      current_batch.update!(
        status: :pending,
        completed_at: Time.current
      )

      current_batch
    rescue StandardError => e
      if current_batch&.persisted?
        current_batch.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: "#{e.class}: #{e.message}"
        )
      end
      raise
    ensure
      self.current_batch = nil
    end

    # Stages a change for a record.
    #
    # @param record [ApplicationRecord] The record being changed
    # @param operation [Symbol] :create or :update
    # @param identifier [String] Human-readable identifier for the record
    def self.stage_change(record, operation:, identifier:)
      raise "No current batch - call within with_staged_batch block" unless current_batch

      diff = case operation
             when :create
               # For creates, all non-nil attributes are "new"
               record.attributes.compact.transform_values { |v| [nil, v] }
             when :update
               # For updates, use ActiveRecord's changes hash
               record.changes.transform_values { |old_new| old_new }
             else
               raise ArgumentError, "Unknown operation: #{operation}"
             end

      current_batch.staged_changes.create!(
        record_type: record.class.name,
        record_id: record.id,
        record_identifier: identifier,
        operation: operation,
        diff: diff
      )

      # Update summary counts
      key = operation == :create ? "created" : "updated"
      current_batch.summary[key] += 1
    end

    # Checks for pending batches and handles according to configuration.
    #
    # @param entity_type [String] The entity type to check
    # @raise [RuntimeError] If a pending batch exists and blocking is enabled
    def self.check_pending_batch!(entity_type)
      pending = StagedBatch.pending.where(entity_type: entity_type).first
      return unless pending

      # For now, we block. TODO: Make this configurable (block vs supersede)
      raise "Pending batch exists for #{entity_type} (ID: #{pending.id}). " \
            "Approve or reject it before running again."
    end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/processor/base_staging_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/processor/base_staging_test.rb
git commit -m "feat: add staging methods to Processors::Base

Adds with_staged_batch and stage_change methods for processors
to write changes to staging tables instead of directly to the database."
```

---

### Task 3.2: Refactor Processors::Operator::Operator to Use Staging

**Files:**
- Modify: `app/models/processors/operator/operator.rb`
- Create: `test/processor/operator_staging_test.rb`

**Step 1: Write integration test**

```ruby
# frozen_string_literal: true

require "test_helper"

class OperatorStagingTest < ActiveSupport::TestCase
  setup do
    # Clear any existing staged batches
    StagedBatch.destroy_all

    # Create test source records
    @vrs_source = Source::Operator::VRSDataOperatorSource.create!(
      name: "Test Airline",
      icao_code: "TST",
      iata_code: "TS",
      data: {}
    )
  end

  test "combine_sources creates a staged batch" do
    assert_difference "StagedBatch.count", 1 do
      Processors::Operator::Operator.combine_sources
    end
  end

  test "combine_sources does not create operators directly" do
    assert_no_difference "Operator.count" do
      Processors::Operator::Operator.combine_sources
    end
  end

  test "combine_sources creates staged changes" do
    batch = Processors::Operator::Operator.combine_sources

    assert batch.staged_changes.any?
    assert_equal "Operator", batch.staged_changes.first.record_type
  end

  test "apply! creates the operators" do
    batch = Processors::Operator::Operator.combine_sources

    assert_difference "Operator.count", 1 do
      batch.apply!(by: nil)
    end

    operator = Operator.find_by(icao_code: "TST")
    assert_equal "Test Airline", operator.name
  end

  test "staged batch has correct summary" do
    batch = Processors::Operator::Operator.combine_sources

    assert_equal 1, batch.summary["created"]
    assert_equal 0, batch.summary["updated"]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/processor/operator_staging_test.rb
```
Expected: FAIL - operators are created directly (old behaviour)

**Step 3: Refactor the processor**

This is a larger refactor. The key changes:
1. Wrap `combine_sources` in `with_staged_batch`
2. Replace `operator.save!` with `stage_change`
3. Remove direct database writes

Modify `app/models/processors/operator/operator.rb`. Replace the `combine_sources` method and related private methods.

I'll provide the key changes. The full implementation requires updating the `merge_sources` and `create_from_single_source` methods to use staging:

```ruby
# In combine_sources method, wrap the whole thing:
def self.combine_sources(triggered_by: nil)
  with_staged_batch(entity_type: "Operator", triggered_by: triggered_by) do
    preload_reference_data

    # ... existing processing logic ...

    # Instead of operator.save!, use:
    # stage_operator_change(operator, is_new: is_new)
  end
end

# Add new helper method:
def self.stage_operator_change(operator, is_new:)
  operation = is_new ? :create : :update
  identifier = operator.icao_code || operator.iata_code || operator.name

  stage_change(operator, operation: operation, identifier: identifier)
end
```

**Note:** The full refactor of this processor is complex. For the implementation plan, this task outlines the approach. The actual implementation should carefully migrate each save operation to staging.

**Step 4: Run tests to verify they pass**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails test test/processor/operator_staging_test.rb
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/processors/operator/operator.rb test/processor/operator_staging_test.rb
git commit -m "refactor: migrate Operators processor to use staging

Operators processor now writes to staging tables instead of directly
to the database. Changes require approval before being applied."
```

---

## Phase 4: Console/Rake Tools

### Task 4.1: Create Processor Rake Tasks

**Files:**
- Create: `lib/tasks/processors.rake`

**Step 1: Write the rake file**

```ruby
# frozen_string_literal: true

namespace :processors do
  desc "Run a processor (enqueues background job)"
  task :run, [:entity_type] => :environment do |_t, args|
    entity_type = args[:entity_type]
    abort "Usage: rake processors:run[EntityType] (e.g., processors:run[Aircraft])" if entity_type.blank?

    processor_class = "Processors::#{entity_type}::#{entity_type}"

    # Verify the processor exists
    begin
      processor_class.constantize
    rescue NameError
      abort "Unknown processor: #{processor_class}"
    end

    job = ProcessorJob.perform_later(processor_class)
    puts "Enqueued #{processor_class}"
    puts "Job ID: #{job.job_id}"
  end

  desc "Run a processor synchronously (for debugging)"
  task :run_sync, [:entity_type] => :environment do |_t, args|
    entity_type = args[:entity_type]
    abort "Usage: rake processors:run_sync[EntityType]" if entity_type.blank?

    processor_class = "Processors::#{entity_type}::#{entity_type}".constantize

    puts "Running #{processor_class}..."
    batch = processor_class.combine_sources

    puts "Completed."
    puts "Batch ID: #{batch.id}"
    puts "Status: #{batch.status}"
    puts "Summary: #{batch.summary}"
  end

  desc "List all available processors"
  task list: :environment do
    processors = Dir[Rails.root.join("app/models/processors/**/")].map do |dir|
      entity = File.basename(dir)
      next if entity == "." || entity == "processors"

      processor_file = File.join(dir, "#{entity}.rb")
      entity.camelize if File.exist?(processor_file)
    end.compact

    puts "Available processors:"
    processors.each { |p| puts "  - #{p}" }
  end
end
```

**Step 2: Test the rake tasks**

Run:
```bash
RBENV_VERSION=3.3.7 bin/rails processors:list
```
Expected: Lists available processors.

**Step 3: Commit**

```bash
git add lib/tasks/processors.rake
git commit -m "feat: add processor rake tasks

Adds rake tasks for:
- processors:run[Entity] - enqueue background job
- processors:run_sync[Entity] - run synchronously
- processors:list - list available processors"
```

---

### Task 4.2: Create Staged Batches Rake Tasks

**Files:**
- Create: `lib/tasks/staged_batches.rake`

**Step 1: Write the rake file**

```ruby
# frozen_string_literal: true

namespace :staged_batches do
  desc "List pending batches"
  task pending: :environment do
    batches = StagedBatch.pending.recent

    if batches.empty?
      puts "No pending batches."
    else
      puts format("%-36s %-15s %-30s %s", "ID", "Entity", "Created", "Summary")
      puts "-" * 100
      batches.each do |batch|
        summary = "#{batch.summary['created'] || 0} created, #{batch.summary['updated'] || 0} updated"
        puts format("%-36s %-15s %-30s %s", batch.id, batch.entity_type, batch.created_at, summary)
      end
    end
  end

  desc "Show batch details"
  task :show, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    puts "Batch: #{batch.id}"
    puts "Processor: #{batch.processor_type}"
    puts "Entity: #{batch.entity_type}"
    puts "Status: #{batch.status}"
    puts "Created: #{batch.created_at}"
    puts "Summary: #{batch.summary}"
    puts ""
    puts "Changes (first 10):"
    batch.staged_changes.limit(10).each do |change|
      puts "  #{change.operation.upcase} #{change.record_type} #{change.record_identifier}"
      change.diff.each do |field, (old_val, new_val)|
        puts "    #{field}: #{old_val.inspect} -> #{new_val.inspect}"
      end
    end

    remaining = batch.staged_changes.count - 10
    puts "  ... and #{remaining} more" if remaining.positive?
  end

  desc "Apply a pending batch"
  task :apply, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    unless batch.pending?
      abort "Batch is not pending (status: #{batch.status})"
    end

    print "Apply #{batch.staged_changes.count} changes to #{batch.entity_type}? [y/N] "
    response = $stdin.gets.chomp.downcase

    if response == "y"
      batch.apply!(by: nil)
      puts "Applied successfully."
    else
      puts "Cancelled."
    end
  end

  desc "Reject a pending batch"
  task :reject, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    unless batch.pending?
      abort "Batch is not pending (status: #{batch.status})"
    end

    print "Reason (optional): "
    reason = $stdin.gets.chomp
    reason = nil if reason.blank?

    batch.reject!(by: nil, reason: reason)
    puts "Batch rejected."
  end

  desc "List recent batches (all statuses)"
  task :history, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 20).to_i
    batches = StagedBatch.recent.limit(limit)

    puts format("%-36s %-15s %-12s %-20s %s", "ID", "Entity", "Status", "Created", "Summary")
    puts "-" * 110
    batches.each do |batch|
      summary = "#{batch.summary['created'] || 0}c/#{batch.summary['updated'] || 0}u"
      puts format("%-36s %-15s %-12s %-20s %s", batch.id, batch.entity_type, batch.status, batch.created_at.strftime("%Y-%m-%d %H:%M"), summary)
    end
  end
end
```

**Step 2: Commit**

```bash
git add lib/tasks/staged_batches.rake
git commit -m "feat: add staged_batches rake tasks

Adds rake tasks for:
- staged_batches:pending - list pending batches
- staged_batches:show[id] - show batch details
- staged_batches:apply[id] - apply a batch
- staged_batches:reject[id] - reject a batch
- staged_batches:history - list recent batches"
```

---

## Summary

This plan covers Phases 1-4 of the implementation:

1. **Core Infrastructure** (Tasks 1.1-1.5): Database tables and models
2. **ActiveJob Setup** (Task 2.1): Background job processing
3. **Processor Integration** (Tasks 3.1-3.2): Staging methods and Operator refactor
4. **Console/Rake Tools** (Tasks 4.1-4.2): CLI interface

**Remaining phases** (to be planned separately):
- Phase 5: Admin Web UI
- Phase 6: Notifications
- Phase 7: Rollback
- Phase 8: Scheduling

**After completing Phase 4**, you'll have a working staged diffs system that can be operated via console and rake tasks. The web UI can be added incrementally.
