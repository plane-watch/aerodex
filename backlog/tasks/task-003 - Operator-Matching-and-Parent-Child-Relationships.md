---
id: task-003
title: Operator Matching and Parent-Child Relationships
status: To Do
assignee: []
created_date: '2026-01-18 17:00'
updated_date: '2026-01-18 17:00'
labels: []
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This task addresses fundamental issues with operator matching, deduplication, and data quality in the Aerodex pipeline.

**Current Problems:**

1. **Cache collision bug** - When multiple operators share a canonical name key (e.g., "virginaustralia"), only one gets cached. Which operator matches depends on database iteration order (non-deterministic).

2. **Operator stub pollution** - Aircraft import creates operator stubs when no match is found, leading to 12,000+ operators with no ICAO codes that pollute the operator table.

3. **No parent-child relationships** - Military/government operators like Royal Air Force have multiple ICAO codes (ACW, RRR, RRF, SHF) representing different operational units, but share a name. These should be modelled as children of a parent organisation.

4. **No match decision persistence** - Matching relies entirely on algorithm. When humans correct a match, the system doesn't learn from it.

5. **Private owner confusion** - Private aircraft owners (e.g., "HASTWELL, David") are being treated the same as commercial operators, creating inappropriate stub records.

6. **Over-aggressive canonicalisation** - Current `aggressive_canonical_key` strips "regional", "international", "cargo" etc., incorrectly merging separate subsidiaries (e.g., "Virgin Australia Regional Airlines" → "virginaustralia" same as "Virgin Australia").

**Goals:**

- Deterministic, predictable operator matching
- Clean operator table with only legitimate operators
- Parent-child hierarchy for multi-unit organisations (RAF, CAA, etc.)
- Human-reviewable queue for unmatched operators
- Learning from corrections over time
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cache collision fix: operators with ICAO codes are preferred over stubs when multiple share a canonical key
- [ ] #2 Aircraft model allows optional operator (remove presence validation)
- [ ] #3 Aircraft import no longer creates operator stubs
- [ ] #4 Private owner detection: if operator_name = owner, leave operator_id null (owner field suffices)
- [ ] #5 Unmatched commercial operators are logged for review (not silently dropped)
- [ ] #6 Parent-child operator relationship via parent_operator_id column
- [ ] #7 Operators with same normalised name + country but different ICAO codes are linked as siblings under a parent
- [ ] #8 Aircraft assigned to parent operator when specific child cannot be determined
- [ ] #9 Match decisions table stores confirmed/rejected operator matches
- [ ] #10 Match decisions are checked before algorithmic matching during aircraft import
- [ ] #11 Pending match decisions queue is visible for human review
- [ ] #12 Re-running aircraft combine applies confirmed match decisions
- [ ] #13 Documentation updated for new operator hierarchy and matching system
- [ ] #14 Existing data migrated: parent-child relationships created for RAF, CAA, etc.
- [ ] #15 Canonicalisation preserves differentiating terms (regional, cargo, international) while stripping generic terms (airlines, airways, pty ltd)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation Plan

### Phase 1: Fix Cache Collision Bug (Quick Win)

**Problem:** `@operators_by_normalised_name` stores single operator per key; last one wins.

**Solution:** Store arrays, pick best candidate at match time.

```ruby
# In Processors::Aircraft::Aircraft

def load_lookup_caches
  # Store ALL operators per canonical key
  @operators_by_normalised_name = Hash.new { |h, k| h[k] = [] }

  ::Operator.find_each do |op|
    key = aggressive_canonical_key(op.name)
    @operators_by_normalised_name[key] << op if key.present?
  end
end

def find_best_operator_for_key(key, country_id: nil)
  candidates = @operators_by_normalised_name[key]
  return nil if candidates.empty?

  # Filter by country if provided
  candidates = candidates.select { |op| op.country_id == country_id } if country_id

  # Prefer parent operators for ambiguous matches
  parent = candidates.find(&:parent?)
  return parent if parent

  # Otherwise prefer operators with ICAO > IATA > neither
  candidates.max_by do |op|
    score = 0
    score += 100 if op.icao_code.present?
    score += 50 if op.iata_code.present?
    score
  end
end
```

**Files to modify:**
- `app/models/processors/aircraft/aircraft.rb`

---

### Phase 1.5: Fix Over-Aggressive Canonicalisation

**Problem:** Current `aggressive_canonical_key` strips terms like "regional", "international", "cargo" that actually differentiate separate operators.

```ruby
# Current behaviour (wrong):
aggressive_canonical_key("Virgin Australia")                    # => "virginaustralia"
aggressive_canonical_key("Virgin Australia Regional Airlines")  # => "virginaustralia" ← WRONG
```

**Solution:** Only strip truly generic terms, preserve differentiating ones.

```ruby
# In OperatorNameCanonicalisation

# Terms that DON'T add uniqueness - safe to strip
GENERIC_TERMS = %w[
  airlines airline airways airway aviation air aero aeronautics
  helicopters helicopter heli heliservices
  services service
  flying flight flights
  charter charters
  group holdings
].freeze

# NOTE: Do NOT strip these - they indicate different operators:
# regional, international, domestic, cargo, freight, express, link

GENERIC_TERMS_PATTERN = /\b(#{GENERIC_TERMS.join('|')})\b/i

def aggressive_canonical_key(name)
  return '' if name.blank?

  key = name.to_s.strip
  key = key.sub(CORPORATE_SUFFIX_PATTERN, '')  # Strip "Pty Ltd" etc.
  key = key.gsub(GENERIC_TERMS_PATTERN, '')    # Strip only generic terms
  key = key.downcase.gsub(/[^a-z0-9]/, '')
  key
end
```

**After fix:**
```ruby
aggressive_canonical_key("Virgin Australia")                    # => "virginaustralia"
aggressive_canonical_key("Virgin Australia Regional Airlines")  # => "virginaustraliaregional" ← CORRECT
aggressive_canonical_key("Qantas")                              # => "qantas"
aggressive_canonical_key("QantasLink")                          # => "qantaslink" ← stays separate
```

**Files to modify:**
- `app/models/concerns/operator_name_canonicalisation.rb`

---

### Phase 2: Make Operator Optional on Aircraft

**Changes:**

```ruby
# app/models/aircraft.rb

belongs_to :operator, counter_cache: true, optional: true

# REMOVE this line:
# validates :operator, presence: true, allow_blank: false
```

**Views already handle nil:**
- `aircraft/show.html.erb` has `<% if @aircraft.operator %>`
- `aircraft/_aircraft.html.erb` uses `aircraft.operator&.name || 'Unknown Operator'`

**Files to modify:**
- `app/models/aircraft.rb`

---

### Phase 3: Stop Creating Operator Stubs

**Replace stub creation with logging and private owner detection:**

```ruby
# In Processors::Aircraft::Aircraft#assign_operator

def assign_operator(record, sources)
  source_with_operator = sources
    .select { |s| s.operator_name.present? || s.operator_icao.present? }
    .max_by { |s| TrustCalculator.new(s, field: :operator_name, entity_type: ENTITY_TYPE).calculate }

  return unless source_with_operator

  # Strategy 1: ICAO lookup (authoritative)
  if source_with_operator.operator_icao.present?
    operator = @operators_by_icao[source_with_operator.operator_icao]
    if operator
      record.operator = operator
      return
    end
    # Has ICAO but no match - don't fall through, log for review
    log_unmatched_operator(record.icao, source_with_operator.operator_name, source_with_operator.operator_icao)
    return
  end

  # Strategy 2: Exact name match
  if source_with_operator.operator_name.present?
    operator = @operators_by_name[source_with_operator.operator_name.downcase]
    if operator
      record.operator = operator
      return
    end
  end

  # Strategy 3: Normalised name match
  if source_with_operator.operator_name.present?
    key = aggressive_canonical_key(source_with_operator.operator_name)
    country_id = cached_country_for_source(source_with_operator)&.id
    operator = find_best_operator_for_key(key, country_id: country_id)
    if operator
      record.operator = operator
      return
    end
  end

  # Strategy 4: Check for private owner (operator = owner)
  if source_with_operator.operator_name.present?
    owner_name = sources.map(&:owner).compact.first
    if owner_name.present? && names_effectively_match?(source_with_operator.operator_name, owner_name)
      # Private owner - owner field is sufficient, no Operator record needed
      return
    end

    # Unmatched commercial operator - log for review
    log_unmatched_operator(record.icao, source_with_operator.operator_name, nil)
  end
end

def names_effectively_match?(name1, name2)
  aggressive_canonical_key(name1) == aggressive_canonical_key(name2)
end

def log_unmatched_operator(aircraft_icao, operator_name, operator_icao)
  @unmatched_operators ||= Hash.new { |h, k| h[k] = { icao: nil, aircraft: [] } }
  key = operator_name.downcase
  @unmatched_operators[key][:icao] ||= operator_icao
  @unmatched_operators[key][:aircraft] << aircraft_icao
end

def report_unmatched_operators
  return if @unmatched_operators.blank?

  Rails.logger.info "=== Unmatched Operators (#{@unmatched_operators.size} unique names) ==="
  @unmatched_operators
    .sort_by { |_name, data| -data[:aircraft].size }
    .first(50)
    .each do |name, data|
      Rails.logger.info "  #{data[:aircraft].size.to_s.rjust(5)} aircraft | ICAO: #{data[:icao] || 'nil'} | #{name}"
    end
end
```

**Files to modify:**
- `app/models/processors/aircraft/aircraft.rb`

---

### Phase 4: Parent-Child Operator Relationships

**Migration:**

```ruby
class AddParentOperatorToOperators < ActiveRecord::Migration[8.0]
  def change
    add_column :operators, :parent_operator_id, :bigint, null: true
    add_foreign_key :operators, :operators, column: :parent_operator_id
    add_index :operators, :parent_operator_id
  end
end
```

**Model changes:**

```ruby
# app/models/operator.rb

belongs_to :parent_operator, class_name: 'Operator', optional: true
has_many :child_operators, class_name: 'Operator', foreign_key: :parent_operator_id

def parent? = child_operators.exists?
def child? = parent_operator_id.present?
def standalone? = !parent? && !child?
```

**Processor to detect and create relationships:**

```ruby
# app/models/processors/operator/operator.rb

def self.create_parent_child_relationships
  include OperatorNameCanonicalisation

  # Group by (canonical_key, country_id)
  groups = ::Operator.includes(:country).group_by do |op|
    [aggressive_canonical_key(op.name), op.country_id]
  end

  created_parents = 0
  linked_children = 0

  groups.each do |(key, country_id), operators|
    next if operators.size < 2

    # Check if they have different ICAO codes (genuine siblings)
    icao_codes = operators.map(&:icao_code).compact.uniq
    next unless icao_codes.size > 1

    # Find or create parent
    parent = operators.find { |op| op.icao_code.blank? && op.parent_operator_id.nil? }

    if parent.nil?
      # Create parent from first operator's name
      country = ::Country.find_by(id: country_id)
      parent = ::Operator.create!(
        name: operators.first.name,
        country: country,
        icao_code: nil,
        iata_code: nil
      )
      created_parents += 1
    end

    # Link children
    operators.each do |op|
      next if op == parent
      next if op.parent_operator_id.present?

      op.update!(parent_operator_id: parent.id)
      linked_children += 1
    end
  end

  Rails.logger.info "Created #{created_parents} parent operators, linked #{linked_children} children"
  { created_parents: created_parents, linked_children: linked_children }
end
```

**Files to create/modify:**
- `db/migrate/XXXXXX_add_parent_operator_to_operators.rb`
- `app/models/operator.rb`
- `app/models/processors/operator/operator.rb`

---

### Phase 5: Match Decisions Table

**Migration:**

```ruby
class CreateOperatorMatchDecisions < ActiveRecord::Migration[8.0]
  def change
    create_table :operator_match_decisions do |t|
      t.string :input_name, null: false
      t.integer :input_country_id
      t.string :canonical_key, null: false
      t.references :matched_operator, foreign_key: { to_table: :operators }
      t.string :match_method  # 'exact', 'canonical', 'fuzzy', 'manual', 'unmatched'
      t.float :confidence
      t.string :status, default: 'pending'  # 'pending', 'confirmed', 'rejected'
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end

    add_index :operator_match_decisions, :canonical_key
    add_index :operator_match_decisions, :status
    add_index :operator_match_decisions, [:input_name, :input_country_id], unique: true
  end
end
```

**Model:**

```ruby
# app/models/operator_match_decision.rb

class OperatorMatchDecision < ApplicationRecord
  belongs_to :matched_operator, class_name: 'Operator', optional: true
  belongs_to :input_country, class_name: 'Country', optional: true
  belongs_to :decided_by, class_name: 'User', optional: true

  validates :input_name, presence: true
  validates :canonical_key, presence: true
  validates :status, inclusion: { in: %w[pending confirmed rejected] }

  scope :pending, -> { where(status: 'pending') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :rejected, -> { where(status: 'rejected') }

  def confirm!(operator, user:)
    update!(
      matched_operator: operator,
      status: 'confirmed',
      decided_by: user,
      decided_at: Time.current,
      match_method: 'manual'
    )
  end

  def reject!(user:)
    update!(
      matched_operator: nil,
      status: 'rejected',
      decided_by: user,
      decided_at: Time.current
    )
  end
end
```

**Integration with aircraft import:**

```ruby
# In Processors::Aircraft::Aircraft

def find_operator_by_match_decision(name, country_id)
  key = aggressive_canonical_key(name)

  decision = OperatorMatchDecision
    .confirmed
    .where(canonical_key: key)
    .where(input_country_id: [country_id, nil])
    .first

  decision&.matched_operator
end

def record_pending_match_decision(name, country_id)
  key = aggressive_canonical_key(name)

  OperatorMatchDecision.find_or_create_by!(
    input_name: name,
    input_country_id: country_id
  ) do |d|
    d.canonical_key = key
    d.status = 'pending'
    d.match_method = 'unmatched'
  end
end
```

**Files to create:**
- `db/migrate/XXXXXX_create_operator_match_decisions.rb`
- `app/models/operator_match_decision.rb`

**Files to modify:**
- `app/models/processors/aircraft/aircraft.rb`

---

### Phase 6: Admin UI for Match Decisions (Future)

Create a simple admin interface to:
- View pending match decisions with aircraft counts
- Confirm a decision (select operator from suggestions)
- Reject a decision (mark as private owner or invalid)
- Create new operator from decision

This can be built using existing Administrate setup or a custom controller.

**Files to create (future):**
- `app/controllers/admin/operator_match_decisions_controller.rb`
- `app/views/admin/operator_match_decisions/`

---

### Phase 7: Data Migration

After deploying schema changes:

```ruby
# Rake task or Rails console

# 1. Create parent-child relationships for existing operators
Processors::Operator::Operator.create_parent_child_relationships

# 2. Re-run aircraft combine to apply new matching logic
Processors::Aircraft::Aircraft.combine_sources

# 3. Review pending match decisions
puts OperatorMatchDecision.pending.count
```

---

### Technical Notes

1. **No breaking API changes** - Aircraft with null operator_id return `operator: null` in JSON
2. **Search unaffected** - Meilisearch attributes already use safe navigation
3. **Counter caches** - `Operator.aircraft_count` will exclude unmatched aircraft (expected)
4. **Idempotent** - Parent-child creation can be re-run safely
5. **Reversible** - Match decisions can be changed; re-running combine applies new decisions
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Background

This design emerged from a brainstorming session analysing the current operator matching issues:

- 792 canonical key collision groups in current data
- 12,000+ operator stubs created by aircraft import
- RAF/CAA units incorrectly merged or kept as confusing duplicates
- "QANTAS AIRWAYS LIMITED" not matching "Qantas" (now fixed by Tim's `aggressive_canonical_key`)

Tim Raphael's commit `74615b0` improved canonicalisation but didn't address:
- Cache collision (non-deterministic matching)
- Stub creation
- Parent-child relationships
- Match decision persistence

This task completes the work by addressing the architectural issues.

## Related Analysis

Example problematic data:

**Royal Air Force (UK) - 5 ICAO codes, one name:**
- ACW - Air Cadet Schools
- RRR - RAF HQSTC (Air Transport)
- RRF - RAF positioning flights
- SHF - Support Helicopter Force
- RFR - (main?)

**Virgin Australia - 4 records, should be 1 (mainline) + 1 (regional):**
- ID 1: Virgin Australia (VOZ) ← correct, mainline
- ID 9667: VIRGIN AUSTRALIA INTERNATIONAL AIRLINES PTY LTD (nil) ← stub, should merge with VOZ
- ID 9756: VIRGIN AUSTRALIA AIRLINES PTY LTD (nil) ← stub, should merge with VOZ
- ID 11852: VIRGIN AUSTRALIA REGIONAL AIRLINES PTY LTD (nil) ← separate operator (different AOC)

## Design Philosophy: "Good Enough"

Aviation operator data is inherently messy. Perfect regulatory accuracy is impossible with available data sources.

**What we know:**
- ICAO code is our best proxy for AOC (Air Operator Certificate)
- Each ICAO code typically represents a separate AOC holder
- Our sources (VRS, OpenTravel, AirlineCodes) don't provide AOC information

**What we accept:**
- ICAO ≠ AOC in all cases (e.g., VARA uses old Skywest AOC but operates as VOZ)
- Wet leasing arrangements mean owner ≠ operator in complex ways
- We cannot model this correctly from available data

**Our approach:**
- ICAO code is the primary identifier
- Same ICAO = same operator (even if AOC reality is more complex)
- Different ICAO = different operator (even if same corporate parent)
- Parent-child relationships capture organisational structure where names match
- Match decisions table lets humans fix edge cases
- Accept that some edge cases will be "wrong" from regulatory perspective but "right" from flight tracking perspective

This is pragmatic, not perfect. The goal is operationally useful data, not regulatory compliance documentation.
<!-- SECTION:NOTES:END -->