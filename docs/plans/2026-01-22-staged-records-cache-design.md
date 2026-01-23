# Staged Records Cache Design

**Status: Implemented** (2026-01-22)

## Problem

When processors use staged batches, records are captured as diffs but not saved to the database. This breaks deduplication logic that relies on database lookups.

### Example: Operator Processor with ICAO "AYD"

Three source records share ICAO code "AYD":
- VRS: "Aladia Airlines"
- OpenTravel: "AB Aviation" (different name)
- AirlineCodes: "Aladia Airlines"

**Current behaviour:**
1. Phase 1: VRS processed, no OTD match (names differ), creates Operator, stages CREATE
2. Phase 2: OTD processed, `find_existing_operator_from_sources` queries DB for ICAO "AYD" - **not found** (only staged)
3. Creates second Operator, stages another CREATE

**Result:** Two CREATE operations for the same ICAO code.

### Root Cause

`find_existing_operator_from_sources` at `app/models/processors/operator/operator.rb:549-579` queries the database:

```ruby
operator = ::Operator.find_by(icao_code: icao_codes)
```

Staged records don't exist in the database, so subsequent lookups fail to find them.

## Solution

Add an in-memory staged records cache to `Processors::Base` that:
1. Stores staged record objects during processing
2. Indexes them by configurable fields for fast lookup
3. Provides a `find_staged_or_persisted` method that checks both cache and database

## Implementation

### Cache Structure

Thread-local storage alongside `current_batch`:

```ruby
# Structure: { ModelClass => { field_name => { downcased_value => record } } }
#
# Example:
# {
#   Operator => {
#     icao_code: { "ayd" => <Operator>, "qfa" => <Operator> },
#     name: { "qantas" => <Operator> }
#   }
# }
```

### New Methods in `Processors::Base`

#### 1. Cache accessor (thread-local)

```ruby
def self.staged_records_cache
  Thread.current[:processor_staged_records_cache]
end

def self.staged_records_cache=(cache)
  Thread.current[:processor_staged_records_cache] = cache
end
```

#### 2. Declare indexed fields

Called at start of processing to specify which fields to index for a model:

```ruby
def self.index_staged_records_by(model_class, *fields)
  staged_records_cache[model_class] ||= {}
  fields.each do |field|
    staged_records_cache[model_class][field] ||= {}
  end
end
```

#### 3. Cache a record

Called by `stage_change` to index the record:

```ruby
def self.cache_staged_record(record)
  model_cache = staged_records_cache[record.class]
  return unless model_cache  # No indexing configured for this model

  model_cache.each_key do |field|
    value = record.public_send(field)
    next if value.blank?

    key = value.to_s.downcase
    model_cache[field][key] = record
  end
end
```

#### 4. Lookup in staged cache only

```ruby
def self.find_in_staged_cache(model_class, **criteria)
  model_cache = staged_records_cache[model_class]
  return nil unless model_cache

  criteria.each do |field, value|
    next unless model_cache[field]

    # Handle array of values (e.g., icao_code: ["AYD", "QFA"])
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

#### 5. Lookup in cache then database

```ruby
def self.find_staged_or_persisted(model_class, **criteria)
  # Check staged cache first
  record = find_in_staged_cache(model_class, **criteria)
  return record if record

  # Fall back to database
  model_class.find_by(**criteria)
end
```

### Modified `stage_change`

Add caching after creating the StagedChange:

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

  # NEW: Cache the record for subsequent lookups within this batch
  cache_staged_record(record)

  key = operation == :create ? "created" : "updated"
  current_batch.summary[key] += 1
end
```

### Modified `with_staged_batch`

Initialise and clear the cache:

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
  self.staged_records_cache = {}  # NEW: Initialise cache

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
  self.staged_records_cache = nil  # NEW: Clear cache
end
```

## Operator Processor Changes

### In `combine_sources`

Add index declaration after preloading reference data:

```ruby
def combine_sources(triggered_by: nil)
  with_staged_batch(entity_type: "Operator", triggered_by: triggered_by) do
    preload_reference_data

    # NEW: Declare indexed fields for staged record lookups
    index_staged_records_by(::Operator, :icao_code, :name)

    # ... rest unchanged ...
  end
end
```

### In `find_existing_operator_from_sources`

Replace database queries with the new method:

```ruby
def find_existing_operator_from_sources(sources)
  icao_codes = sources.map(&:icao_code).compact.uniq
  has_icao = icao_codes.any?

  if has_icao
    # NEW: Checks staged cache first, then database
    operator = find_staged_or_persisted(::Operator, icao_code: icao_codes)
    return operator if operator
    return nil
  end

  # Name fallback - also uses the new method
  names = sources.map(&:name).compact.uniq
  names.each do |name|
    operator = find_staged_or_persisted(::Operator, name: name)
    return operator if operator
  end

  nil
end
```

## Expected Behaviour After Fix

With ICAO "AYD" example:

**Phase 1:** VRS "Aladia Airlines" (ICAO: AYD)
1. No OTD match (name mismatch with "AB Aviation")
2. `find_existing_operator_from_sources` → cache empty → DB empty → returns nil
3. Creates new Operator in memory
4. `stage_change` → creates StagedChange AND caches record under `icao_code: "ayd"` and `name: "aladia airlines"`

**Phase 2:** OTD "AB Aviation" (ICAO: AYD)
1. Unmatched, calls `create_from_single_source`
2. `find_existing_operator_from_sources` → cache hit for `icao_code: "ayd"` → **returns staged Operator**
3. Returns existing record with `is_new = false`
4. Updates the operator fields based on trust scores
5. `stage_change` with operation `:update`, cache updated

**Result:** 1 CREATE + 1 UPDATE for the same operator (correct behaviour).

## Files to Modify

1. `app/models/processors/base.rb` - Add cache infrastructure and new methods
2. `app/models/processors/operator/operator.rb` - Use new lookup method
3. `test/models/processors/base_test.rb` - Add tests for cache methods
4. `test/models/processors/operator/operator_test.rb` - Add test for the "AYD" scenario

## Future Considerations

Other processors could adopt this pattern if they have similar multi-phase processing. Currently, Manufacturer and Aircraft processors pre-group by unique identifier, avoiding the issue. If their patterns change, they can use `index_staged_records_by` and `find_staged_or_persisted` as needed.

## Implementation Notes

The name-based fallback lookup in `find_existing_operator_from_sources` uses a separate path for cache and database lookups to preserve case-insensitivity in the database query (`LOWER(name) = ?`), whilst the cache lookup is already case-insensitive by design.
