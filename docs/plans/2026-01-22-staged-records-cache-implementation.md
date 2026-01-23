# Staged Records Cache Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add in-memory cache to `Processors::Base` so staged records can be found during multi-phase processing, fixing duplicate creation bug in Operator processor.

**Architecture:** Thread-local cache stores staged record objects indexed by configurable fields. `stage_change` populates cache; new `find_staged_or_persisted` method checks cache before database. Cache cleared at end of `with_staged_batch`.

**Tech Stack:** Ruby, Rails, Minitest

---

## Task 1: Add Cache Accessor Methods to Base Processor

**Files:**
- Modify: `app/models/processors/base.rb:176-185`

**Step 1: Write the failing test**

Create test file first:

```ruby
# test/models/processors/base_test.rb
# frozen_string_literal: true

require "test_helper"

class Processors::BaseTest < ActiveSupport::TestCase
  setup do
    # Clear any existing thread-local state
    Processors::Base.send(:current_batch=, nil)
    Processors::Base.send(:staged_records_cache=, nil)
  end

  teardown do
    Processors::Base.send(:current_batch=, nil)
    Processors::Base.send(:staged_records_cache=, nil)
  end

  # ---------------------------------------------------------------------------
  # staged_records_cache accessor tests
  # ---------------------------------------------------------------------------

  test "staged_records_cache returns nil by default" do
    assert_nil Processors::Base.staged_records_cache
  end

  test "staged_records_cache can be set and retrieved" do
    cache = { Operator => { icao_code: {} } }
    Processors::Base.send(:staged_records_cache=, cache)

    assert_equal cache, Processors::Base.staged_records_cache
  end

  test "staged_records_cache is thread-local" do
    Processors::Base.send(:staged_records_cache=, { main: true })

    thread_value = nil
    Thread.new do
      thread_value = Processors::Base.staged_records_cache
    end.join

    assert_nil thread_value, "Expected cache to be nil in other thread"
    assert_equal({ main: true }, Processors::Base.staged_records_cache)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: FAIL with "undefined method `staged_records_cache'"

**Step 3: Write minimal implementation**

Add after `current_batch=` method (around line 185):

```ruby
    # Thread-local storage for staged records cache during processing.
    # Structure: { ModelClass => { field_name => { downcased_value => record } } }
    #
    # @return [Hash, nil] The cache or nil if not in a batch
    def self.staged_records_cache
      Thread.current[:processor_staged_records_cache]
    end

    # Sets the staged records cache in thread-local storage.
    #
    # @param cache [Hash, nil] The cache to set
    def self.staged_records_cache=(cache)
      Thread.current[:processor_staged_records_cache] = cache
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/models/processors/base_test.rb app/models/processors/base.rb
git commit -m "$(cat <<'EOF'
feat(processors): add staged_records_cache accessor methods

Add thread-local storage for caching staged records during batch
processing. This will enable lookups of records that have been
staged but not yet persisted to the database.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add index_staged_records_by Method

**Files:**
- Modify: `app/models/processors/base.rb`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # index_staged_records_by tests
  # ---------------------------------------------------------------------------

  test "index_staged_records_by initialises cache structure for model and fields" do
    Processors::Base.send(:staged_records_cache=, {})

    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    expected = {
      Operator => {
        icao_code: {},
        name: {}
      }
    }
    assert_equal expected, Processors::Base.staged_records_cache
  end

  test "index_staged_records_by preserves existing cache entries" do
    existing_operator = Operator.new(icao_code: "QFA", name: "Qantas")
    Processors::Base.send(:staged_records_cache=, {
      Operator => {
        icao_code: { "qfa" => existing_operator }
      }
    })

    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    assert_equal existing_operator, Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
    assert_equal({}, Processors::Base.staged_records_cache[Operator][:name])
  end

  test "index_staged_records_by can register multiple model classes" do
    Processors::Base.send(:staged_records_cache=, {})

    Processors::Base.index_staged_records_by(Operator, :icao_code)
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    assert Processors::Base.staged_records_cache.key?(Operator)
    assert Processors::Base.staged_records_cache.key?(Manufacturer)
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:50 -v`
Expected: FAIL with "undefined method `index_staged_records_by'"

**Step 3: Write minimal implementation**

Add after the cache accessor methods:

```ruby
    # Declares which fields to index for staged record lookups.
    #
    # Call at the start of processing to specify which fields should be
    # indexed for fast lookups. Only indexed fields can be used with
    # find_staged_or_persisted.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param fields [Array<Symbol>] The field names to index
    #
    # @example
    #   index_staged_records_by(Operator, :icao_code, :name)
    def self.index_staged_records_by(model_class, *fields)
      staged_records_cache[model_class] ||= {}
      fields.each do |field|
        staged_records_cache[model_class][field] ||= {}
      end
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): add index_staged_records_by method

Allows processors to declare which fields should be indexed for
staged record lookups. This sets up the cache structure for the
specified model and fields.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add cache_staged_record Method

**Files:**
- Modify: `app/models/processors/base.rb`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # cache_staged_record tests
  # ---------------------------------------------------------------------------

  test "cache_staged_record indexes record by declared fields" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    operator = Operator.new(icao_code: "QFA", name: "Qantas Airways")
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
    assert_equal operator, Processors::Base.staged_records_cache[Operator][:name]["qantas airways"]
  end

  test "cache_staged_record uses case-insensitive keys" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: "QFA")
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
  end

  test "cache_staged_record skips blank field values" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code, :iata_code)

    operator = Operator.new(icao_code: "QFA", iata_code: nil)
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
    assert_empty Processors::Base.staged_records_cache[Operator][:iata_code]
  end

  test "cache_staged_record does nothing if model not indexed" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    operator = Operator.new(icao_code: "QFA")
    Processors::Base.cache_staged_record(operator)

    assert_not Processors::Base.staged_records_cache.key?(Operator)
  end

  test "cache_staged_record overwrites existing entry for same key" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator1 = Operator.new(icao_code: "QFA", name: "Old Name")
    operator2 = Operator.new(icao_code: "QFA", name: "New Name")

    Processors::Base.cache_staged_record(operator1)
    Processors::Base.cache_staged_record(operator2)

    cached = Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
    assert_equal "New Name", cached.name
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:80 -v`
Expected: FAIL with "undefined method `cache_staged_record'"

**Step 3: Write minimal implementation**

Add after `index_staged_records_by`:

```ruby
    # Caches a staged record for subsequent lookups within the batch.
    #
    # Indexes the record by all declared fields (via index_staged_records_by).
    # Uses case-insensitive keys for string values.
    #
    # @param record [ApplicationRecord] The record to cache
    def self.cache_staged_record(record)
      model_cache = staged_records_cache[record.class]
      return unless model_cache

      model_cache.each_key do |field|
        value = record.public_send(field)
        next if value.blank?

        key = value.to_s.downcase
        model_cache[field][key] = record
      end
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): add cache_staged_record method

Indexes a record by all declared fields for fast lookup. Uses
case-insensitive keys. Called by stage_change to populate the
cache automatically.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add find_in_staged_cache Method

**Files:**
- Modify: `app/models/processors/base.rb`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # find_in_staged_cache tests
  # ---------------------------------------------------------------------------

  test "find_in_staged_cache returns cached record by single field" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: "QFA", name: "Qantas")
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: "QFA")
    assert_equal operator, result
  end

  test "find_in_staged_cache is case-insensitive" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: "QFA")
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: "qfa")
    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: "QFA")
    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: "Qfa")
  end

  test "find_in_staged_cache returns nil when not found" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: "NOTFOUND")
    assert_nil result
  end

  test "find_in_staged_cache handles array of values" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: "QFA")
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: ["JST", "QFA", "SIA"])
    assert_equal operator, result
  end

  test "find_in_staged_cache returns first match from array" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    qantas = Operator.new(icao_code: "QFA", name: "Qantas")
    jetstar = Operator.new(icao_code: "JST", name: "Jetstar")
    Processors::Base.cache_staged_record(qantas)
    Processors::Base.cache_staged_record(jetstar)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: ["JST", "QFA"])
    assert_equal jetstar, result
  end

  test "find_in_staged_cache returns nil if model not indexed" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: "QFA")
    assert_nil result
  end

  test "find_in_staged_cache returns nil if field not indexed" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: "QFA", name: "Qantas")
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, name: "Qantas")
    assert_nil result
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:130 -v`
Expected: FAIL with "undefined method `find_in_staged_cache'"

**Step 3: Write minimal implementation**

Add after `cache_staged_record`:

```ruby
    # Looks up a record in the staged cache only.
    #
    # Searches by the provided criteria fields. Returns the first match found.
    # Uses case-insensitive matching for string values.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param criteria [Hash] Field/value pairs to search by
    # @return [ApplicationRecord, nil] The cached record or nil
    #
    # @example Single value lookup
    #   find_in_staged_cache(Operator, icao_code: "QFA")
    #
    # @example Array of values (returns first match)
    #   find_in_staged_cache(Operator, icao_code: ["QFA", "JST"])
    def self.find_in_staged_cache(model_class, **criteria)
      model_cache = staged_records_cache[model_class]
      return nil unless model_cache

      criteria.each do |field, value|
        next unless model_cache[field]

        values = Array(value)
        values.each do |v|
          key = v.to_s.downcase
          record = model_cache[field][key]
          return record if record
        end
      end

      nil
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): add find_in_staged_cache method

Looks up records in the staged cache by field criteria. Supports
single values or arrays. Uses case-insensitive matching.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add find_staged_or_persisted Method

**Files:**
- Modify: `app/models/processors/base.rb`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # find_staged_or_persisted tests
  # ---------------------------------------------------------------------------

  test "find_staged_or_persisted returns cached record if present" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    cached_operator = Operator.new(icao_code: "TESTCACHE", name: "Cached")
    Processors::Base.cache_staged_record(cached_operator)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: "TESTCACHE")
    assert_equal cached_operator, result
  end

  test "find_staged_or_persisted falls back to database" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    # Create a persisted operator
    db_operator = Operator.create!(icao_code: "TESTDB", name: "Database Operator")

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: "TESTDB")
    assert_equal db_operator, result
  ensure
    Operator.where(icao_code: "TESTDB").delete_all
  end

  test "find_staged_or_persisted prefers cache over database" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    # Create persisted operator
    Operator.create!(icao_code: "TESTBOTH", name: "Database Version")

    # Cache a different record with same key
    cached_operator = Operator.new(icao_code: "TESTBOTH", name: "Cached Version")
    Processors::Base.cache_staged_record(cached_operator)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: "TESTBOTH")
    assert_equal "Cached Version", result.name
  ensure
    Operator.where(icao_code: "TESTBOTH").delete_all
  end

  test "find_staged_or_persisted returns nil when not found anywhere" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: "NONEXISTENT")
    assert_nil result
  end

  test "find_staged_or_persisted handles array criteria for database" do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    db_operator = Operator.create!(icao_code: "TESTARR", name: "Array Test")

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: ["NOTFOUND", "TESTARR"])
    assert_equal db_operator, result
  ensure
    Operator.where(icao_code: "TESTARR").delete_all
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:195 -v`
Expected: FAIL with "undefined method `find_staged_or_persisted'"

**Step 3: Write minimal implementation**

Add after `find_in_staged_cache`:

```ruby
    # Looks up a record in the staged cache first, then falls back to database.
    #
    # This is the primary lookup method for processors during batch processing.
    # It ensures that recently staged records can be found even though they
    # haven't been persisted yet.
    #
    # @param model_class [Class] The ActiveRecord model class
    # @param criteria [Hash] Field/value pairs to search by
    # @return [ApplicationRecord, nil] The record or nil
    #
    # @example
    #   find_staged_or_persisted(Operator, icao_code: "QFA")
    #   find_staged_or_persisted(Operator, icao_code: ["QFA", "JST"])
    def self.find_staged_or_persisted(model_class, **criteria)
      # Check staged cache first
      record = find_in_staged_cache(model_class, **criteria)
      return record if record

      # Fall back to database
      model_class.find_by(**criteria)
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): add find_staged_or_persisted method

Primary lookup method that checks staged cache first, then falls
back to database. Enables processors to find recently staged
records that haven't been persisted yet.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Modify with_staged_batch to Manage Cache Lifecycle

**Files:**
- Modify: `app/models/processors/base.rb:196-228`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # with_staged_batch cache lifecycle tests
  # ---------------------------------------------------------------------------

  test "with_staged_batch initialises empty cache" do
    # Use a test processor class
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { "TestProcessor" }

    cache_during_block = nil

    test_processor.with_staged_batch(entity_type: "Test") do
      cache_during_block = Processors::Base.staged_records_cache
    end

    assert_equal({}, cache_during_block)
  end

  test "with_staged_batch clears cache after completion" do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { "TestProcessor" }

    test_processor.with_staged_batch(entity_type: "Test") do
      Processors::Base.index_staged_records_by(Operator, :icao_code)
      operator = Operator.new(icao_code: "TEST")
      Processors::Base.cache_staged_record(operator)
    end

    assert_nil Processors::Base.staged_records_cache
  end

  test "with_staged_batch clears cache on error" do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { "TestProcessor" }

    assert_raises(RuntimeError) do
      test_processor.with_staged_batch(entity_type: "Test") do
        Processors::Base.index_staged_records_by(Operator, :icao_code)
        raise "Test error"
      end
    end

    assert_nil Processors::Base.staged_records_cache
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:245 -v`
Expected: FAIL (cache not initialised or not cleared)

**Step 3: Modify with_staged_batch**

Update `with_staged_batch` method to initialise and clear the cache:

```ruby
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
      self.staged_records_cache = {}

      yield

      current_batch.update!(
        status: :pending,
        completed_at: Time.current,
        summary: current_batch.summary
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
      self.staged_records_cache = nil
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): manage cache lifecycle in with_staged_batch

Initialises empty cache at start of batch processing and clears
it in the ensure block, even on error. This ensures the cache is
always available during processing and cleaned up afterwards.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Modify stage_change to Cache Records

**Files:**
- Modify: `app/models/processors/base.rb:240-265`
- Modify: `test/models/processors/base_test.rb`

**Step 1: Write the failing test**

Add to `test/models/processors/base_test.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # stage_change caching tests
  # ---------------------------------------------------------------------------

  test "stage_change caches the record" do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { "TestProcessor" }

    test_processor.with_staged_batch(entity_type: "Operator") do
      Processors::Base.index_staged_records_by(Operator, :icao_code)

      operator = Operator.new(icao_code: "STAGETEST", name: "Stage Test")
      Processors::Base.stage_change(operator, operation: :create, identifier: "STAGETEST")

      cached = Processors::Base.find_in_staged_cache(Operator, icao_code: "STAGETEST")
      assert_equal operator, cached
    end
  end

  test "stage_change caches update operations" do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { "TestProcessor" }

    existing = Operator.create!(icao_code: "UPDATETEST", name: "Old Name")

    test_processor.with_staged_batch(entity_type: "Operator") do
      Processors::Base.index_staged_records_by(Operator, :icao_code)

      existing.name = "New Name"
      Processors::Base.stage_change(existing, operation: :update, identifier: "UPDATETEST")

      cached = Processors::Base.find_in_staged_cache(Operator, icao_code: "UPDATETEST")
      assert_equal "New Name", cached.name
    end
  ensure
    Operator.where(icao_code: "UPDATETEST").delete_all
  end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/base_test.rb:280 -v`
Expected: FAIL (cached record not found)

**Step 3: Modify stage_change**

Add `cache_staged_record(record)` call after creating the StagedChange:

```ruby
    def self.stage_change(record, operation:, identifier:)
      raise "No current batch - call within with_staged_batch block" unless current_batch

      diff = case operation
             when :create
               record.attributes.compact.transform_values { |v| [nil, v] }
             when :update
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

      # Cache the record for subsequent lookups within this batch
      cache_staged_record(record)

      key = operation == :create ? "created" : "updated"
      current_batch.summary[key] += 1
    end
```

**Step 4: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/base_test.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/processors/base.rb test/models/processors/base_test.rb
git commit -m "$(cat <<'EOF'
feat(processors): cache records in stage_change

Automatically caches staged records for subsequent lookups within
the same batch. This enables processors to find records that were
staged earlier in the same processing run.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update Operator Processor to Use Cache

**Files:**
- Modify: `app/models/processors/operator/operator.rb:235-278` (combine_sources)
- Modify: `app/models/processors/operator/operator.rb:549-579` (find_existing_operator_from_sources)

**Step 1: Create test file with failing test for the AYD scenario**

```ruby
# test/models/processors/operator/operator_test.rb
# frozen_string_literal: true

require "test_helper"

class Processors::Operator::OperatorTest < ActiveSupport::TestCase
  # Test ICAO codes that won't conflict with real data
  TEST_ICAO_CODES = %w[ZZAYD ZZTST ZZDUP].freeze

  setup do
    StagedBatch.delete_all
    StagedChange.delete_all

    # Clear operator sources
    Source::Operator::VRSDataOperatorSource.delete_all
    Source::Operator::OpenTravelOperatorSource.delete_all
    Source::Operator::AirlineCodesOperatorSource.delete_all

    # Clean up test operators
    Operator.where(icao_code: TEST_ICAO_CODES).delete_all

    SourceTrustScore.clear_cache!
  end

  teardown do
    Operator.where(icao_code: TEST_ICAO_CODES).delete_all
  end

  # ---------------------------------------------------------------------------
  # Duplicate ICAO code handling (the "AYD" scenario)
  # ---------------------------------------------------------------------------

  test "combine_sources does not create duplicates for same ICAO with different names" do
    # This reproduces the bug where VRS "Aladia Airlines" and OTD "AB Aviation"
    # both have ICAO "AYD" but different names, resulting in two CREATE operations.

    # Create VRS source with one name
    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: "ZZAYD",
      name: "Aladia Airlines",
      import_date: Time.current
    )

    # Create OTD source with SAME ICAO but DIFFERENT name
    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: "ZZAYD",
      iata_code: "Y6",
      name: "AB Aviation",
      import_date: Time.current
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should be 1 CREATE + 1 UPDATE, not 2 CREATEs
    creates = batch.staged_changes.creates.count
    updates = batch.staged_changes.updates.count

    assert_equal 1, creates, "Expected exactly 1 CREATE for ICAO ZZAYD"
    assert updates <= 1, "Expected at most 1 UPDATE for ICAO ZZAYD"

    # All staged changes should reference the same ICAO
    icao_identifiers = batch.staged_changes.pluck(:record_identifier)
    assert icao_identifiers.all? { |id| id == "ZZAYD" },
           "Expected all changes to reference ZZAYD, got: #{icao_identifiers.inspect}"
  end

  test "combine_sources correctly merges sources with same ICAO and similar names" do
    # When names are similar enough to match, they should merge cleanly
    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: "ZZTST",
      name: "Test Airways",
      import_date: Time.current
    )

    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: "ZZTST",
      name: "Test Airways", # Same name
      import_date: Time.current
    )

    batch = Processors::Operator::Operator.combine_sources

    # Should merge into single CREATE
    assert_equal 1, batch.staged_changes.creates.count
    assert_equal 0, batch.staged_changes.updates.count
  end

  test "combine_sources finds staged operator in phase 2" do
    # Three sources with same ICAO: VRS + two OTD records
    # Phase 1 processes VRS, Phase 2 should find staged record for remaining OTD

    Source::Operator::VRSDataOperatorSource.create!(
      icao_code: "ZZDUP",
      name: "First Name",
      import_date: Time.current
    )

    Source::Operator::OpenTravelOperatorSource.create!(
      icao_code: "ZZDUP",
      name: "Second Name",
      import_date: Time.current
    )

    batch = Processors::Operator::Operator.combine_sources

    # Verify we don't have duplicate CREATEs
    create_count = batch.staged_changes.creates.count
    assert_equal 1, create_count, "Expected 1 CREATE, got #{create_count}"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `./bin/rails test test/models/processors/operator/operator_test.rb -v`
Expected: FAIL with "Expected exactly 1 CREATE for ICAO ZZAYD"

**Step 3: Update combine_sources to declare indexed fields**

In `app/models/processors/operator/operator.rb`, add index declaration after `preload_reference_data`:

```ruby
        def combine_sources(triggered_by: nil)
          with_staged_batch(entity_type: "Operator", triggered_by: triggered_by) do
            preload_reference_data

            # Declare indexed fields for staged record lookups.
            # This enables find_staged_or_persisted to find operators staged
            # earlier in this batch when processing unmatched sources.
            index_staged_records_by(::Operator, :icao_code, :name)

            errors = []
            conflicts = []
            # ... rest unchanged
```

**Step 4: Update find_existing_operator_from_sources**

Replace database queries with `find_staged_or_persisted`:

```ruby
        def find_existing_operator_from_sources(sources)
          icao_codes = sources.map(&:icao_code).compact.uniq
          has_icao = icao_codes.any?

          if has_icao
            # Check staged cache first, then database
            operator = find_staged_or_persisted(::Operator, icao_code: icao_codes)
            return operator if operator

            # Source has ICAO but no match found - do NOT fall through to IATA/name search.
            return nil
          end

          # Fall back to exact name match (case-insensitive) - only if no ICAO code
          names = sources.map(&:name).compact.uniq
          names.each do |name|
            operator = find_staged_or_persisted(::Operator, name: name)
            return operator if operator
          end

          nil
        end
```

**Step 5: Run test to verify it passes**

Run: `./bin/rails test test/models/processors/operator/operator_test.rb -v`
Expected: PASS

**Step 6: Commit**

```bash
git add app/models/processors/operator/operator.rb test/models/processors/operator/operator_test.rb
git commit -m "$(cat <<'EOF'
fix(operator): use staged cache to prevent duplicate creates

Update Operator processor to use find_staged_or_persisted when
looking for existing operators. This fixes a bug where sources
with the same ICAO code but different names would create duplicate
operators instead of updating the first one.

The processor now declares :icao_code and :name as indexed fields,
enabling cache lookups during multi-phase processing.

Fixes the "AYD" duplicate scenario where VRS "Aladia Airlines"
and OTD "AB Aviation" both have ICAO "AYD".

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Run Full Test Suite

**Step 1: Run all processor tests**

Run: `./bin/rails test test/models/processors/ -v`
Expected: All tests PASS

**Step 2: Run full test suite**

Run: `./bin/rails test`
Expected: All tests PASS

**Step 3: Commit any final adjustments**

If any tests fail, fix them and commit.

---

## Task 10: Update Design Document

**Files:**
- Modify: `docs/plans/2026-01-22-staged-records-cache-design.md`

**Step 1: Add "Implemented" status to design doc**

Add at the top of the design document:

```markdown
**Status:** Implemented (2026-01-22)
```

**Step 2: Commit**

```bash
git add docs/plans/2026-01-22-staged-records-cache-design.md
git commit -m "$(cat <<'EOF'
docs: mark staged records cache design as implemented

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```
