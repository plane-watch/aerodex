# Processor Staging Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all 6 remaining combine processors to use the staging pattern, enabling admin review before changes are applied to the database.

**Architecture:** Each processor's `combine_sources` method will be refactored to use `with_staged_batch` and `stage_change` instead of direct saves. Changes are captured in `StagedBatch` and `StagedChange` records for review. The existing `FieldMerger` and provenance tracking remain unchanged.

**Tech Stack:** Rails 7, Minitest, existing Processors::Base staging infrastructure

**Design Document:** `docs/plans/2026-01-20-staged-diffs-admin-ui-design.md`

**Reference Implementation:** `app/models/processors/operator/operator.rb` (already migrated)

---

## Task 0: Baseline Test Coverage

Add pre-refactoring tests for all 6 processors to ensure behaviour is preserved after migration.

### Task 0.1: Country Processor Baseline Tests

**Files:**
- Create: `test/models/processors/country/country_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Country::CountryTest < ActiveSupport::TestCase
  setup do
    # Clear any existing data
    Country.delete_all
    Source::Country::OpenTravelCountrySource.delete_all
    Source::Country::OpenFlightsCountrySource.delete_all
    Source::Country::OurAirportsCountrySource.delete_all
  end

  test "combine_sources creates country from sources" do
    # Create source records
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "ZZ",
      iso_3char_code: "ZZZ",
      name: "Test Country"
    )

    Processors::Country::Country.combine_sources

    country = Country.find_by(iso_2char_code: "ZZ")
    assert_not_nil country
    assert_equal "Test Country", country.name
    assert_equal "ZZZ", country.iso_3char_code
  end

  test "combine_sources updates existing country when source has changes" do
    # Create existing country
    Country.create!(
      iso_2char_code: "YY",
      iso_3char_code: "YYY",
      name: "Old Name"
    )

    # Create source with updated name
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "YY",
      iso_3char_code: "YYY",
      name: "New Name"
    )

    Processors::Country::Country.combine_sources

    country = Country.find_by(iso_2char_code: "YY")
    assert_equal "New Name", country.name
  end

  test "combine_sources merges multiple sources using trust scores" do
    # Create conflicting sources - higher trust score should win
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "XX",
      iso_3char_code: "XXX",
      name: "OpenTravel Name"
    )
    Source::Country::OpenFlightsCountrySource.create!(
      iso_2char_code: "XX",
      iso_3char_code: "XXX",
      name: "OpenFlights Name"
    )

    Processors::Country::Country.combine_sources

    country = Country.find_by(iso_2char_code: "XX")
    assert_not_nil country
    # The winning name depends on trust scores - just verify one was chosen
    assert_includes ["OpenTravel Name", "OpenFlights Name"], country.name
  end

  test "combine_sources sets provenance for fields" do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "WW",
      iso_3char_code: "WWW",
      name: "Provenance Test"
    )

    Processors::Country::Country.combine_sources

    country = Country.find_by(iso_2char_code: "WW")
    assert_not_nil country.provenance
    assert country.provenance.key?("name") || country.provenance.key?(:name)
  end
end
```

**Step 2: Run test to verify it passes**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/country/country_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/country/country_test.rb
git commit -m "test: add baseline tests for Country processor"
```

---

### Task 0.2: Manufacturer Processor Baseline Tests

**Files:**
- Create: `test/models/processors/manufacturer/manufacturer_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Manufacturer::ManufacturerTest < ActiveSupport::TestCase
  setup do
    Manufacturer.delete_all
    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.delete_all
  end

  test "combine_sources creates manufacturer from sources" do
    # CFAPPS source contains manufacturer info embedded in aircraft type records
    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "B738",
      manufacturer: "Boeing",
      model: "737-800"
    )

    Processors::Manufacturer::Manufacturer.combine_sources

    manufacturer = Manufacturer.find_by(name: "Boeing")
    assert_not_nil manufacturer
  end

  test "combine_sources does not duplicate existing manufacturers" do
    Manufacturer.create!(name: "Airbus")

    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "A320",
      manufacturer: "Airbus",
      model: "A320"
    )

    assert_no_difference "Manufacturer.count" do
      Processors::Manufacturer::Manufacturer.combine_sources
    end
  end

  test "combine_sources normalises manufacturer names" do
    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "C172",
      manufacturer: "CESSNA",
      model: "172"
    )

    Processors::Manufacturer::Manufacturer.combine_sources

    # Should normalise to title case or similar
    manufacturer = Manufacturer.where("LOWER(name) = ?", "cessna").first
    assert_not_nil manufacturer
  end
end
```

**Step 2: Run test**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/manufacturer/manufacturer_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/manufacturer/manufacturer_test.rb
git commit -m "test: add baseline tests for Manufacturer processor"
```

---

### Task 0.3: AircraftType Processor Baseline Tests

**Files:**
- Create: `test/models/processors/aircraft_type/aircraft_type_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::AircraftType::AircraftTypeTest < ActiveSupport::TestCase
  setup do
    AircraftType.delete_all
    Manufacturer.delete_all
    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.delete_all
    Source::AircraftType::OpenFlightsAircraftTypeSource.delete_all
  end

  test "combine_sources creates aircraft type from sources" do
    manufacturer = Manufacturer.create!(name: "Boeing")

    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "B738",
      manufacturer: "Boeing",
      model: "737-800"
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(icao_code: "B738")
    assert_not_nil aircraft_type
    assert_equal "737-800", aircraft_type.model
    assert_equal manufacturer.id, aircraft_type.manufacturer_id
  end

  test "combine_sources updates existing aircraft type" do
    manufacturer = Manufacturer.create!(name: "Boeing")
    AircraftType.create!(
      icao_code: "B738",
      model: "Old Model",
      manufacturer: manufacturer
    )

    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "B738",
      manufacturer: "Boeing",
      model: "737-800"
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(icao_code: "B738")
    assert_equal "737-800", aircraft_type.model
  end

  test "combine_sources links to correct manufacturer" do
    boeing = Manufacturer.create!(name: "Boeing")
    airbus = Manufacturer.create!(name: "Airbus")

    Source::AircraftType::CfappsIcaoIntAircraftTypeSource.create!(
      icao_code: "A320",
      manufacturer: "Airbus",
      model: "A320"
    )

    Processors::AircraftType::AircraftType.combine_sources

    aircraft_type = AircraftType.find_by(icao_code: "A320")
    assert_equal airbus.id, aircraft_type.manufacturer_id
  end
end
```

**Step 2: Run test**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/aircraft_type/aircraft_type_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/aircraft_type/aircraft_type_test.rb
git commit -m "test: add baseline tests for AircraftType processor"
```

---

### Task 0.4: Airport Processor Baseline Tests

**Files:**
- Create: `test/models/processors/airport/airport_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Airport::AirportTest < ActiveSupport::TestCase
  setup do
    Airport.delete_all
    Country.delete_all
    Source::Airport::OpenFlightsAirportSource.delete_all
    Source::Airport::OurAirportsAirportSource.delete_all

    @australia = Country.create!(
      iso_2char_code: "AU",
      iso_3char_code: "AUS",
      name: "Australia"
    )
  end

  test "combine_sources creates airport from sources" do
    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: "YSSY",
      iata_code: "SYD",
      name: "Sydney Kingsford Smith",
      latitude: -33.9461,
      longitude: 151.1772,
      country_code: "AU"
    )

    Processors::Airport::Airport.combine_sources

    airport = Airport.find_by(icao_code: "YSSY")
    assert_not_nil airport
    assert_equal "Sydney Kingsford Smith", airport.name
    assert_equal "SYD", airport.iata_code
    assert_equal @australia.id, airport.country_id
  end

  test "combine_sources updates existing airport" do
    Airport.create!(
      icao_code: "YMML",
      name: "Old Name",
      country: @australia
    )

    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: "YMML",
      iata_code: "MEL",
      name: "Melbourne Airport",
      country_code: "AU"
    )

    Processors::Airport::Airport.combine_sources

    airport = Airport.find_by(icao_code: "YMML")
    assert_equal "Melbourne Airport", airport.name
  end

  test "combine_sources merges multiple sources" do
    Source::Airport::OurAirportsAirportSource.create!(
      icao_code: "YBBN",
      name: "Brisbane Airport",
      country_code: "AU"
    )
    Source::Airport::OpenFlightsAirportSource.create!(
      icao_code: "YBBN",
      iata_code: "BNE",
      name: "Brisbane International",
      country_code: "AU"
    )

    Processors::Airport::Airport.combine_sources

    airport = Airport.find_by(icao_code: "YBBN")
    assert_not_nil airport
    # Should have IATA from OpenFlights
    assert_equal "BNE", airport.iata_code
  end
end
```

**Step 2: Run test**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/airport/airport_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/airport/airport_test.rb
git commit -m "test: add baseline tests for Airport processor"
```

---

### Task 0.5: Runway Processor Baseline Tests

**Files:**
- Create: `test/models/processors/runway/runway_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Runway::RunwayTest < ActiveSupport::TestCase
  setup do
    Runway.delete_all
    Airport.delete_all
    Country.delete_all
    Source::Runway::OurAirportsRunwaySource.delete_all

    @australia = Country.create!(
      iso_2char_code: "AU",
      iso_3char_code: "AUS",
      name: "Australia"
    )
    @sydney = Airport.create!(
      icao_code: "YSSY",
      name: "Sydney",
      country: @australia
    )
  end

  test "combine_sources creates runway from sources" do
    Source::Runway::OurAirportsRunwaySource.create!(
      airport_icao: "YSSY",
      le_ident: "16R",
      he_ident: "34L",
      length_ft: 12999,
      width_ft: 148,
      surface: "ASP"
    )

    Processors::Runway::Runway.combine_sources

    runway = Runway.find_by(airport: @sydney, le_ident: "16R")
    assert_not_nil runway
    assert_equal "34L", runway.he_ident
    assert_equal 12999, runway.length_ft
  end

  test "combine_sources updates existing runway" do
    Runway.create!(
      airport: @sydney,
      le_ident: "16L",
      he_ident: "34R",
      length_ft: 10000
    )

    Source::Runway::OurAirportsRunwaySource.create!(
      airport_icao: "YSSY",
      le_ident: "16L",
      he_ident: "34R",
      length_ft: 11000,
      surface: "ASP"
    )

    Processors::Runway::Runway.combine_sources

    runway = Runway.find_by(airport: @sydney, le_ident: "16L")
    assert_equal 11000, runway.length_ft
  end

  test "combine_sources skips runways for unknown airports" do
    Source::Runway::OurAirportsRunwaySource.create!(
      airport_icao: "XXXX",
      le_ident: "01",
      he_ident: "19"
    )

    assert_no_difference "Runway.count" do
      Processors::Runway::Runway.combine_sources
    end
  end
end
```

**Step 2: Run test**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/runway/runway_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/runway/runway_test.rb
git commit -m "test: add baseline tests for Runway processor"
```

---

### Task 0.6: Aircraft Processor Baseline Tests

**Files:**
- Create: `test/models/processors/aircraft/aircraft_test.rb`

**Step 1: Create the test file**

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Aircraft::AircraftTest < ActiveSupport::TestCase
  setup do
    Aircraft.delete_all
    Operator.delete_all
    AircraftType.delete_all
    Manufacturer.delete_all
    Country.delete_all

    @australia = Country.create!(
      iso_2char_code: "AU",
      iso_3char_code: "AUS",
      name: "Australia"
    )
    @manufacturer = Manufacturer.create!(name: "Boeing")
    @aircraft_type = AircraftType.create!(
      icao_code: "B738",
      model: "737-800",
      manufacturer: @manufacturer
    )
    @operator = Operator.create!(
      name: "Qantas",
      icao_code: "QFA",
      country: @australia
    )

    # Clear source tables
    Source::Aircraft::CasaAircraftSource.delete_all if defined?(Source::Aircraft::CasaAircraftSource)
    Source::Aircraft::OpenskyAircraftSource.delete_all if defined?(Source::Aircraft::OpenskyAircraftSource)
  end

  test "combine_sources creates aircraft from sources" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end

  test "combine_sources updates existing aircraft" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end

  test "combine_sources links to operator and aircraft type" do
    skip "Aircraft processor requires complex source setup - test after migration"
  end
end
```

**Note:** The Aircraft processor is the most complex and may require more detailed fixture setup. These placeholder tests document the expected behaviour; full tests will be written during migration.

**Step 2: Run test**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/aircraft/aircraft_test.rb
```

**Step 3: Commit**

```bash
git add test/models/processors/aircraft/aircraft_test.rb
git commit -m "test: add baseline test structure for Aircraft processor"
```

---

## Task 1: Migrate Country Processor

**Files:**
- Modify: `app/models/processors/country/country.rb`
- Modify: `test/models/processors/country/country_test.rb`

**Step 1: Update combine_sources to use staging**

Replace the `combine_sources` method in `app/models/processors/country/country.rb`:

```ruby
# Combines country data from all available sources into staged changes.
#
# @param triggered_by [User, nil] The user who triggered the run
# @return [StagedBatch] The batch containing staged changes
def combine_sources(triggered_by: nil)
  with_staged_batch(entity_type: "Country", triggered_by: triggered_by) do
    sources_by_iso = group_sources_by_iso
    conflicts = []

    # Ensure trust scores are cached
    SourceTrustScore.send(:ensure_cache_loaded)

    progress_bar = create_progress_bar(sources_by_iso.count)

    sources_by_iso.each do |iso_code, sources|
      record = ::Country.find_or_initialize_by(iso_2char_code: iso_code)

      # Merge each field using FieldMerger
      MERGE_FIELDS.each do |field|
        merger = FieldMerger.new(sources: sources, field: field, entity_type: ENTITY_TYPE)

        record.public_send("#{field}=", merger.best_value)

        # Track provenance for this field
        if merger.best_source && merger.best_value.present?
          record.set_provenance(field, source: merger.best_source, confidence: merger.best_confidence)
        end

        # Collect conflict information for logging
        conflicts << merger.conflict_details if merger.has_conflict?
      end

      record.last_combined_at = Time.current

      # Stage the change instead of saving
      if record.new_record?
        stage_change(record, operation: :create, identifier: iso_code)
      elsif record.changed?
        stage_change(record, operation: :update, identifier: iso_code)
      else
        current_batch.summary["unchanged"] += 1
      end

      progress_bar.increment!
    end

    # Log any conflicts for review
    log_conflicts(conflicts) if conflicts.any?

    # Store conflict count in batch notes if any
    if conflicts.any?
      current_batch.notes = "Processing completed with #{conflicts.count} field conflicts"
    end
  end
end
```

**Step 2: Update tests to verify staging behaviour**

Update `test/models/processors/country/country_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class Processors::Country::CountryTest < ActiveSupport::TestCase
  setup do
    # Clear any existing data
    StagedBatch.delete_all
    StagedChange.delete_all
    Country.delete_all
    Source::Country::OpenTravelCountrySource.delete_all
    Source::Country::OpenFlightsCountrySource.delete_all
    Source::Country::OurAirportsCountrySource.delete_all
  end

  test "combine_sources returns a staged batch" do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "ZZ",
      iso_3char_code: "ZZZ",
      name: "Test Country"
    )

    result = Processors::Country::Country.combine_sources

    assert_instance_of StagedBatch, result
    assert_equal "pending", result.status
    assert_equal "Country", result.entity_type
  end

  test "combine_sources stages country creation" do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "ZZ",
      iso_3char_code: "ZZZ",
      name: "Test Country"
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 1, batch.staged_changes.creates.count
    change = batch.staged_changes.first
    assert_equal "ZZ", change.record_identifier
    assert_equal "Test Country", change.new_values["name"]

    # Country should NOT exist yet
    assert_nil Country.find_by(iso_2char_code: "ZZ")
  end

  test "combine_sources stages country update" do
    Country.create!(
      iso_2char_code: "YY",
      iso_3char_code: "YYY",
      name: "Old Name"
    )

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "YY",
      iso_3char_code: "YYY",
      name: "New Name"
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 1, batch.staged_changes.updates.count
    change = batch.staged_changes.first
    assert_equal "YY", change.record_identifier
    assert_equal ["Old Name", "New Name"], change.diff["name"]
  end

  test "combine_sources tracks unchanged records" do
    Country.create!(
      iso_2char_code: "XX",
      iso_3char_code: "XXX",
      name: "Same Name"
    )

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "XX",
      iso_3char_code: "XXX",
      name: "Same Name"
    )

    batch = Processors::Country::Country.combine_sources

    assert_equal 0, batch.staged_changes.count
    assert_equal 1, batch.summary["unchanged"]
  end

  test "combine_sources accepts triggered_by parameter" do
    user = users(:admin)

    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "WW",
      iso_3char_code: "WWW",
      name: "Test"
    )

    batch = Processors::Country::Country.combine_sources(triggered_by: user)

    assert_equal user, batch.created_by
  end

  test "applying batch creates the country" do
    Source::Country::OpenTravelCountrySource.create!(
      iso_2char_code: "VV",
      iso_3char_code: "VVV",
      name: "Applied Country"
    )

    batch = Processors::Country::Country.combine_sources

    assert_nil Country.find_by(iso_2char_code: "VV")

    batch.apply!(by: nil)

    country = Country.find_by(iso_2char_code: "VV")
    assert_not_nil country
    assert_equal "Applied Country", country.name
  end
end
```

**Step 3: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/country/country_test.rb
```

**Step 4: Commit**

```bash
git add app/models/processors/country/country.rb test/models/processors/country/country_test.rb
git commit -m "refactor: migrate Country processor to staging pattern"
```

---

## Task 2: Migrate Manufacturer Processor

**Files:**
- Modify: `app/models/processors/manufacturer/manufacturer.rb`
- Modify: `test/models/processors/manufacturer/manufacturer_test.rb`

**Step 1: Read the current implementation**

Read `app/models/processors/manufacturer/manufacturer.rb` to understand the current logic.

**Step 2: Update combine_sources to use staging**

Follow the same pattern as Country:
- Wrap in `with_staged_batch(entity_type: "Manufacturer", triggered_by: triggered_by)`
- Replace `save!` with `stage_change(record, operation: :create/:update, identifier: name)`
- Track unchanged count
- Remove direct reindex call

**Step 3: Update tests**

Update tests to verify staging behaviour (batch returned, changes staged, records not created until apply).

**Step 4: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/manufacturer/manufacturer_test.rb
```

**Step 5: Commit**

```bash
git add app/models/processors/manufacturer/manufacturer.rb test/models/processors/manufacturer/manufacturer_test.rb
git commit -m "refactor: migrate Manufacturer processor to staging pattern"
```

---

## Task 3: Migrate AircraftType Processor

**Files:**
- Modify: `app/models/processors/aircraft_type/aircraft_type.rb`
- Modify: `test/models/processors/aircraft_type/aircraft_type_test.rb`

**Step 1: Read the current implementation**

This processor has FK to Manufacturer. Note how manufacturer_id is resolved.

**Step 2: Update combine_sources to use staging**

Same pattern, ensuring manufacturer_id is captured in the diff.

**Step 3: Update tests**

**Step 4: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/aircraft_type/aircraft_type_test.rb
```

**Step 5: Commit**

```bash
git add app/models/processors/aircraft_type/aircraft_type.rb test/models/processors/aircraft_type/aircraft_type_test.rb
git commit -m "refactor: migrate AircraftType processor to staging pattern"
```

---

## Task 4: Migrate Airport Processor

**Files:**
- Modify: `app/models/processors/airport/airport.rb`
- Modify: `test/models/processors/airport/airport_test.rb`

**Step 1: Read the current implementation**

This processor has FK to Country. Note how country_id is resolved.

**Step 2: Update combine_sources to use staging**

Same pattern as previous processors.

**Step 3: Update tests**

**Step 4: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/airport/airport_test.rb
```

**Step 5: Commit**

```bash
git add app/models/processors/airport/airport.rb test/models/processors/airport/airport_test.rb
git commit -m "refactor: migrate Airport processor to staging pattern"
```

---

## Task 5: Migrate Runway Processor

**Files:**
- Modify: `app/models/processors/runway/runway.rb`
- Modify: `test/models/processors/runway/runway_test.rb`

**Step 1: Read the current implementation**

This processor has FK to Airport and uses composite key (airport_id + le_ident).

**Step 2: Update combine_sources to use staging**

Identifier should be `"#{airport.icao_code}/#{le_ident}"` for human readability.

**Step 3: Update tests**

**Step 4: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/runway/runway_test.rb
```

**Step 5: Commit**

```bash
git add app/models/processors/runway/runway.rb test/models/processors/runway/runway_test.rb
git commit -m "refactor: migrate Runway processor to staging pattern"
```

---

## Task 6: Migrate Aircraft Processor

**Files:**
- Modify: `app/models/processors/aircraft/aircraft.rb`
- Modify: `test/models/processors/aircraft/aircraft_test.rb`

**Step 1: Read the current implementation**

This is the most complex processor:
- Multiple FKs (operator_id, aircraft_type_id, country_id)
- Uses insert_all/upsert_all for performance
- Large dataset (~500k records)

**Step 2: Consider memory implications**

With 500k records, staging all changes in memory could be problematic. Options:
- Stage in batches (commit staged changes periodically)
- Use streaming/chunked approach
- Accept that large batches may need pagination in the UI (already handled)

**Step 3: Update combine_sources to use staging**

Replace insert_all/upsert_all with individual stage_change calls. This is slower but provides full visibility.

If performance is unacceptable, consider a hybrid approach where creates are batched but still staged.

**Step 4: Update tests**

**Step 5: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/models/processors/aircraft/aircraft_test.rb
```

**Step 6: Commit**

```bash
git add app/models/processors/aircraft/aircraft.rb test/models/processors/aircraft/aircraft_test.rb
git commit -m "refactor: migrate Aircraft processor to staging pattern"
```

---

## Task 7: Enhance Diff View for FK Display

**Files:**
- Modify: `app/helpers/admin/staged_batches_helper.rb`
- Modify: `app/views/admin/staged_batches/_diff.html.erb`
- Modify: `app/controllers/admin/staged_batches_controller.rb`

**Step 1: Add helper method for FK display**

Add to `app/helpers/admin/staged_batches_helper.rb`:

```ruby
# Formats a foreign key value for display, showing the related record's name.
#
# @param field [String] The field name (e.g., "operator_id")
# @param value [Integer, nil] The FK value
# @return [String] Human-readable representation
def format_fk_value(field, value)
  return "null" if value.nil?

  # Extract model name from field (operator_id -> Operator)
  model_name = field.to_s.delete_suffix("_id").classify

  begin
    record = model_name.constantize.find_by(id: value)
    if record
      display_name = record.try(:name) || record.try(:icao_code) || record.try(:code) || record.id.to_s
      "#{display_name} (ID: #{value})"
    else
      "#{value} (not found)"
    end
  rescue NameError
    value.to_s
  end
end

# Checks if a field is a foreign key.
#
# @param field [String] The field name
# @return [Boolean]
def foreign_key_field?(field)
  field.to_s.end_with?("_id") && field.to_s != "id"
end
```

**Step 2: Update diff partial**

Update `app/views/admin/staged_batches/_diff.html.erb`:

```erb
<%# Renders a single diff entry (field change) %>
<%# locals: field, old_value, new_value %>
<div class="flex items-start gap-2 py-1 text-sm font-mono">
  <span class="font-semibold text-gray-600 min-w-[120px]"><%= field %>:</span>
  <% if foreign_key_field?(field) %>
    <span class="text-red-600 line-through"><%= format_fk_value(field, old_value) %></span>
    <span class="text-gray-400">&rarr;</span>
    <span class="text-green-600"><%= format_fk_value(field, new_value) %></span>
  <% else %>
    <span class="text-red-600 line-through"><%= old_value.nil? ? "null" : old_value.inspect %></span>
    <span class="text-gray-400">&rarr;</span>
    <span class="text-green-600"><%= new_value.nil? ? "null" : new_value.inspect %></span>
  <% end %>
</div>
```

**Step 3: Run tests**

```bash
RBENV_VERSION=3.3.7 bin/rails test test/controllers/admin/staged_batches_controller_test.rb
```

**Step 4: Commit**

```bash
git add app/helpers/admin/staged_batches_helper.rb app/views/admin/staged_batches/_diff.html.erb
git commit -m "feat: display FK names in diff browser"
```

---

## Summary

| Task | Description | Estimated Effort |
|------|-------------|------------------|
| 0.1-0.6 | Baseline tests for all 6 processors | Medium |
| 1 | Migrate Country processor | Low |
| 2 | Migrate Manufacturer processor | Low |
| 3 | Migrate AircraftType processor | Medium |
| 4 | Migrate Airport processor | Medium |
| 5 | Migrate Runway processor | Medium |
| 6 | Migrate Aircraft processor | High |
| 7 | FK display enhancement | Low |

**After completing all tasks**, the admin UI will show staged changes for all combine processors, with FK fields displaying human-readable names instead of raw IDs.
