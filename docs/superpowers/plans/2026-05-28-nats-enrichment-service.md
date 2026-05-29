# NATS Enrichment Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose aerodex's aviation reference data over NATS via three read-only request-reply subjects (`v2.enrich.aircraft`, `v2.enrich.route`, `v2.enrich.airport`), served by a dedicated long-lived consumer process.

**Architecture:** A standalone, eager-loaded Rails runner process (`bin/enrichment-server`) connects to NATS with `nats-pure`, subscribes to `v2.enrich.*` under a queue group, and dispatches each message to a per-subject handler. Handlers parse a small JSON request envelope, run an indexed ActiveRecord query, serialise the result to a clean snake_case JSON contract, and reply on the message's inbox. Each message is processed inside `Rails.application.executor.wrap` so ActiveRecord connections are checked out and returned correctly. Prometheus metrics are exposed on a side HTTP port. No caching is built (upstream already caches); the handler/query/serializer split leaves a clean seam to add one later.

**Tech Stack:** Ruby 3.3.7, Rails 8.1.2, PostgreSQL, `nats-pure` (~> 2.5), `prometheus-client`, `webrick` (metrics exposition), Minitest with fixtures.

**Reference spec:** `docs/superpowers/specs/2026-05-28-nats-enrichment-design.md`

---

## File Structure

All new runtime code lives under `app/services/enrichment/` (Zeitwerk maps this to the `Enrichment` module). Tests mirror it under `test/services/enrichment/`.

**Serializers** (PORO, each `self.call(record)` → `Hash` or `nil`):
- `country_serializer.rb` — the shared `country` object.
- `flight_information_region_serializer.rb` — the shared FIR object.
- `manufacturer_serializer.rb` — composes country.
- `operator_serializer.rb` — composes country + shallow parent.
- `aircraft_type_serializer.rb` — composes manufacturer.
- `runway_serializer.rb` — a single runway.
- `airport_summary_serializer.rb` — lean airport (no runways) for route segments; composes country.
- `aircraft_serializer.rb` — composes type, operator, registration_country.
- `airport_serializer.rb` — composes country, FIR, runways.
- `route_serializer.rb` — composes operator + segments (airport_summary).
- `provenance_serializer.rb` — opt-in provenance block (wraps the existing `all_provenance_with_sources`).

**Request handling:**
- `errors.rb` — `Enrichment::BadRequestError`.
- `request_parser.rb` — raw NATS payload (JSON string) → symbolised Hash, or raises `BadRequestError`.
- `handler.rb` — base class: parse → handle → JSON, with error rescues.
- `aircraft_handler.rb`, `route_handler.rb`, `airport_handler.rb` — per-subject handlers.
- `dispatcher.rb` — maps an exact subject string to its handler instance.

**Queries:**
- `aircraft_query.rb`, `route_query.rb`, `airport_query.rb` — indexed lookups with eager loading.

**Process & observability:**
- `metrics.rb` — Prometheus registry + metric definitions + helper methods.
- `metrics_server.rb` — WEBrick `/metrics` HTTP server in a thread.
- `nats_server.rb` — connection lifecycle, subscription, executor wrap, metrics, drain.
- `bin/enrichment-server` — executable that boots Rails and runs `Enrichment::NatsServer`.

**Conventions to follow** (observed in the codebase):
- Every Ruby file starts with `# frozen_string_literal: true`.
- Tests are Minitest (`class XTest < ActiveSupport::TestCase`, `test '...' do`), using the existing fixtures in `test/fixtures/`.
- Australian/British English in comments and docs.
- Comprehensive doc comments on public methods.

---

## Task 1: Add dependencies

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gems**

Add these lines to `Gemfile` after the existing `gem "parallel"` line (line 85):

```ruby
# NATS client for the enrichment service (see docs/superpowers/specs/2026-05-28-nats-enrichment-design.md)
gem "nats-pure", "~> 2.5"

# Prometheus metrics for the enrichment service
gem "prometheus-client", "~> 4.2"

# HTTP server used to expose the enrichment service's Prometheus metrics endpoint
gem "webrick", "~> 1.8"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: bundle resolves and installs `nats-pure`, `prometheus-client`, `webrick`. `Gemfile.lock` updates.

- [ ] **Step 3: Verify the client loads**

Run: `bin/rails runner "require 'nats/client'; require 'prometheus/client'; require 'webrick'; puts 'ok'"`
Expected: prints `ok` with no `LoadError`.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "build: add nats-pure, prometheus-client and webrick for enrichment service"
```

---

## Task 2: Country and FlightInformationRegion serializers

**Files:**
- Create: `app/services/enrichment/country_serializer.rb`
- Create: `app/services/enrichment/flight_information_region_serializer.rb`
- Test: `test/services/enrichment/country_serializer_test.rb`
- Test: `test/services/enrichment/flight_information_region_serializer_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/services/enrichment/country_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::CountrySerializerTest < ActiveSupport::TestCase
  test 'serialises a country to the v2 shape' do
    result = Enrichment::CountrySerializer.call(countries(:australia))

    assert_equal(
      {
        name: 'Australia',
        iso_2char_code: 'AU',
        iso_3char_code: 'AUS',
        iso_num_code: '036',
        capital: 'Canberra'
      },
      result
    )
  end

  test 'returns nil for a nil country' do
    assert_nil Enrichment::CountrySerializer.call(nil)
  end
end
```

`test/services/enrichment/flight_information_region_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::FlightInformationRegionSerializerTest < ActiveSupport::TestCase
  test 'serialises a flight information region to the v2 shape' do
    result = Enrichment::FlightInformationRegionSerializer.call(flight_information_regions(:melbourne))

    assert_equal({ icao_code: 'YMMM', region: 'Melbourne' }, result)
  end

  test 'returns nil for a nil region' do
    assert_nil Enrichment::FlightInformationRegionSerializer.call(nil)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/enrichment/country_serializer_test.rb test/services/enrichment/flight_information_region_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::CountrySerializer`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/country_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises a Country into the shared `country` object used throughout the
  # v2 enrichment contract. Returns nil when no country is present so callers
  # can embed the result directly.
  class CountrySerializer
    # @param country [Country, nil]
    # @return [Hash, nil]
    def self.call(country)
      return nil if country.nil?

      {
        name: country.name,
        iso_2char_code: country.iso_2char_code,
        iso_3char_code: country.iso_3char_code,
        iso_num_code: country.iso_num_code,
        capital: country.capital
      }
    end
  end
end
```

`app/services/enrichment/flight_information_region_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises a FlightInformationRegion into the shallow object embedded in an
  # airport response. Returns nil when the airport has no region.
  class FlightInformationRegionSerializer
    # @param region [FlightInformationRegion, nil]
    # @return [Hash, nil]
    def self.call(region)
      return nil if region.nil?

      {
        icao_code: region.icao_code,
        region: region.region
      }
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/enrichment/country_serializer_test.rb test/services/enrichment/flight_information_region_serializer_test.rb`
Expected: PASS (4 assertions, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/country_serializer.rb app/services/enrichment/flight_information_region_serializer.rb test/services/enrichment/country_serializer_test.rb test/services/enrichment/flight_information_region_serializer_test.rb
git commit -m "feat(enrichment): add country and FIR serializers"
```

---

## Task 3: Manufacturer and Operator serializers

**Files:**
- Create: `app/services/enrichment/manufacturer_serializer.rb`
- Create: `app/services/enrichment/operator_serializer.rb`
- Test: `test/services/enrichment/manufacturer_serializer_test.rb`
- Test: `test/services/enrichment/operator_serializer_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/services/enrichment/manufacturer_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::ManufacturerSerializerTest < ActiveSupport::TestCase
  test 'serialises a manufacturer with its country' do
    result = Enrichment::ManufacturerSerializer.call(manufacturers(:boeing))

    assert_equal 'Boeing', result[:name]
    assert_equal 'BOE', result[:icao_code]
    assert_equal ['The Boeing Company'], result[:alt_names]
    assert_equal 'United States', result[:country][:name]
  end

  test 'defaults alt_names to an empty array when nil' do
    manufacturer = manufacturers(:boeing)
    manufacturer.alt_names = nil

    result = Enrichment::ManufacturerSerializer.call(manufacturer)

    assert_equal [], result[:alt_names]
  end

  test 'returns nil for a nil manufacturer' do
    assert_nil Enrichment::ManufacturerSerializer.call(nil)
  end
end
```

`test/services/enrichment/operator_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::OperatorSerializerTest < ActiveSupport::TestCase
  test 'serialises an operator with its country and a nil parent' do
    result = Enrichment::OperatorSerializer.call(operators(:american_airlines))

    assert_equal 'American Airlines', result[:name]
    assert_equal 'AAL', result[:icao_code]
    assert_equal 'AA', result[:iata_code]
    assert_equal 'United States', result[:country][:name]
    assert_nil result[:parent]
  end

  test 'serialises a shallow parent when present' do
    operator = operators(:american_airlines)
    operator.parent_operator = operators(:united_airlines)

    result = Enrichment::OperatorSerializer.call(operator)

    assert_equal({ name: 'United Airlines', icao_code: 'UAL', iata_code: 'UA' }, result[:parent])
  end

  test 'returns nil for a nil operator' do
    assert_nil Enrichment::OperatorSerializer.call(nil)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/enrichment/manufacturer_serializer_test.rb test/services/enrichment/operator_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::ManufacturerSerializer`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/manufacturer_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises a Manufacturer into the shared `manufacturer` object embedded in
  # an aircraft type. Source/provenance metadata is intentionally excluded.
  class ManufacturerSerializer
    # @param manufacturer [Manufacturer, nil]
    # @return [Hash, nil]
    def self.call(manufacturer)
      return nil if manufacturer.nil?

      {
        name: manufacturer.name,
        icao_code: manufacturer.icao_code,
        alt_names: manufacturer.alt_names || [],
        country: CountrySerializer.call(manufacturer.country)
      }
    end
  end
end
```

`app/services/enrichment/operator_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an Operator into the shared `operator` object. Includes a shallow
  # parent (name and codes only) for multi-unit organisations; the parent has no
  # nested parent or country, to bound the response size.
  class OperatorSerializer
    # @param operator [Operator, nil]
    # @return [Hash, nil]
    def self.call(operator)
      return nil if operator.nil?

      {
        name: operator.name,
        icao_code: operator.icao_code,
        iata_code: operator.iata_code,
        country: CountrySerializer.call(operator.country),
        parent: parent_summary(operator.parent_operator)
      }
    end

    # Builds the shallow parent summary, or nil when there is no parent.
    #
    # @param parent [Operator, nil]
    # @return [Hash, nil]
    def self.parent_summary(parent)
      return nil if parent.nil?

      {
        name: parent.name,
        icao_code: parent.icao_code,
        iata_code: parent.iata_code
      }
    end
    private_class_method :parent_summary
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/enrichment/manufacturer_serializer_test.rb test/services/enrichment/operator_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/manufacturer_serializer.rb app/services/enrichment/operator_serializer.rb test/services/enrichment/manufacturer_serializer_test.rb test/services/enrichment/operator_serializer_test.rb
git commit -m "feat(enrichment): add manufacturer and operator serializers"
```

---

## Task 4: AircraftType serializer

**Files:**
- Create: `app/services/enrichment/aircraft_type_serializer.rb`
- Test: `test/services/enrichment/aircraft_type_serializer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/aircraft_type_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftTypeSerializerTest < ActiveSupport::TestCase
  test 'serialises an aircraft type with its manufacturer and enum category label' do
    result = Enrichment::AircraftTypeSerializer.call(aircraft_types(:boeing_737))

    assert_equal 'B737', result[:type_code]
    assert_equal '737-800', result[:name]
    assert_equal 'Boeing 737-800', result[:full_name]
    assert_equal 'airplane', result[:category]
    assert_equal 'Boeing', result[:manufacturer][:name]
  end

  test 'returns nil for a nil type' do
    assert_nil Enrichment::AircraftTypeSerializer.call(nil)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/aircraft_type_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::AircraftTypeSerializer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/aircraft_type_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an AircraftType into the shared `aircraft_type` object. `category`
  # is the enum label string (e.g. "airplane"); `full_name` uses the model's
  # existing helper (manufacturer name + type name).
  class AircraftTypeSerializer
    # @param type [AircraftType, nil]
    # @return [Hash, nil]
    def self.call(type)
      return nil if type.nil?

      {
        type_code: type.type_code,
        name: type.name,
        full_name: type.full_name,
        category: type.category,
        wtc: type.wtc,
        engines: type.engines,
        engine_type: type.engine_type,
        manufacturer: ManufacturerSerializer.call(type.manufacturer)
      }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/aircraft_type_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/aircraft_type_serializer.rb test/services/enrichment/aircraft_type_serializer_test.rb
git commit -m "feat(enrichment): add aircraft type serializer"
```

---

## Task 5: Runway and AirportSummary serializers

**Files:**
- Create: `app/services/enrichment/runway_serializer.rb`
- Create: `app/services/enrichment/airport_summary_serializer.rb`
- Test: `test/services/enrichment/runway_serializer_test.rb`
- Test: `test/services/enrichment/airport_summary_serializer_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/services/enrichment/runway_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::RunwaySerializerTest < ActiveSupport::TestCase
  test 'serialises a runway, converting decimals to floats' do
    result = Enrichment::RunwaySerializer.call(airport_runways(:yssy_rwy_16r))

    assert_equal '16R', result[:name]
    assert_nil result[:le_ident]
    assert_nil result[:he_ident]
    assert_in_delta 167.85, result[:heading], 0.001
    assert_in_delta 3971.0, result[:length], 0.001
    assert_in_delta 45.0, result[:width], 0.001
    assert_equal false, result[:lighted]
    assert_equal false, result[:closed]
    assert_instance_of Float, result[:heading]
  end

  test 'leaves nil dimensions as nil' do
    runway = airport_runways(:yssy_rwy_16r)
    runway.heading = nil

    result = Enrichment::RunwaySerializer.call(runway)

    assert_nil result[:heading]
  end
end
```

`test/services/enrichment/airport_summary_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportSummarySerializerTest < ActiveSupport::TestCase
  test 'serialises a lean airport with its country and float coordinates' do
    result = Enrichment::AirportSummarySerializer.call(airports(:yssy))

    assert_equal 'YSSY', result[:icao_code]
    assert_equal 'SYD', result[:iata_code]
    assert_equal 'Sydney International Airport', result[:name]
    assert_equal 'Sydney', result[:city]
    assert_in_delta(-33.946111, result[:latitude], 0.000001)
    assert_in_delta 151.177222, result[:longitude], 0.000001
    assert_in_delta 13.0, result[:altitude], 0.001
    assert_equal 'Australia/Sydney', result[:timezone]
    assert_equal 'Australia', result[:country][:name]
    assert_not result.key?(:runways)
  end

  test 'returns nil for a nil airport' do
    assert_nil Enrichment::AirportSummarySerializer.call(nil)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/enrichment/runway_serializer_test.rb test/services/enrichment/airport_summary_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::RunwaySerializer`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/runway_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an AirportRunway. The `heading`, `length` and `width` columns are
  # stored as unit-less decimals (the canonical table does not record units);
  # they are converted to floats so they serialise as JSON numbers rather than
  # strings.
  class RunwaySerializer
    # @param runway [AirportRunway]
    # @return [Hash]
    def self.call(runway)
      {
        name: runway.runway_name,
        le_ident: runway.le_ident,
        he_ident: runway.he_ident,
        heading: runway.heading&.to_f,
        length: runway.length&.to_f,
        width: runway.width&.to_f,
        surface: runway.surface,
        lighted: runway.lighted,
        closed: runway.closed
      }
    end
  end
end
```

`app/services/enrichment/airport_summary_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an Airport into the lean `airport_summary` object embedded in
  # route segments. Deliberately omits runways to keep route responses small;
  # full runways are available via the v2.enrich.airport subject.
  class AirportSummarySerializer
    # @param airport [Airport, nil]
    # @return [Hash, nil]
    def self.call(airport)
      return nil if airport.nil?

      {
        icao_code: airport.icao_code,
        iata_code: airport.iata_code,
        name: airport.name,
        city: airport.city,
        latitude: airport.latitude&.to_f,
        longitude: airport.longitude&.to_f,
        altitude: airport.altitude&.to_f,
        timezone: airport.timezone,
        country: CountrySerializer.call(airport.country)
      }
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/enrichment/runway_serializer_test.rb test/services/enrichment/airport_summary_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/runway_serializer.rb app/services/enrichment/airport_summary_serializer.rb test/services/enrichment/runway_serializer_test.rb test/services/enrichment/airport_summary_serializer_test.rb
git commit -m "feat(enrichment): add runway and airport summary serializers"
```

---

## Task 6: Provenance serializer

**Files:**
- Create: `app/services/enrichment/provenance_serializer.rb`
- Test: `test/services/enrichment/provenance_serializer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/provenance_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::ProvenanceSerializerTest < ActiveSupport::TestCase
  test 'returns the per-field provenance with source metadata' do
    aircraft = aircraft(:one)
    aircraft.field_provenance = {
      'registration' => {
        'source_type' => 'AutoGenerated',
        'source_id' => nil,
        'confidence' => 50,
        'combined_at' => '2026-01-01T00:00:00Z'
      }
    }

    result = Enrichment::ProvenanceSerializer.call(aircraft)

    assert_equal 50, result['registration']['confidence']
    assert_equal 'AutoGenerated', result['registration']['source_type']
  end

  test 'returns nil for a record that does not track provenance' do
    assert_nil Enrichment::ProvenanceSerializer.call(routes(:aa_1))
  end

  test 'returns an empty hash when no fields are tracked' do
    aircraft = aircraft(:one)
    aircraft.field_provenance = {}

    assert_equal({}, Enrichment::ProvenanceSerializer.call(aircraft))
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/provenance_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::ProvenanceSerializer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/provenance_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Builds the opt-in `provenance` block for an entity that tracks field-level
  # provenance via HasFieldProvenance. Delegates to the model's existing
  # all_provenance_with_sources so the per-field shape stays consistent with the
  # rest of the application. Returns nil for records that do not track
  # provenance (e.g. Route), so the caller can omit the block entirely.
  class ProvenanceSerializer
    # @param record [ActiveRecord::Base]
    # @return [Hash, nil]
    def self.call(record)
      return nil unless record.respond_to?(:all_provenance_with_sources)

      record.all_provenance_with_sources
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/provenance_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/provenance_serializer.rb test/services/enrichment/provenance_serializer_test.rb
git commit -m "feat(enrichment): add provenance serializer"
```

---

## Task 7: Aircraft serializer

**Files:**
- Create: `app/services/enrichment/aircraft_serializer.rb`
- Test: `test/services/enrichment/aircraft_serializer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/aircraft_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftSerializerTest < ActiveSupport::TestCase
  test 'serialises an aircraft with nested type, operator and country' do
    result = Enrichment::AircraftSerializer.call(aircraft(:one))

    assert_equal 'n123456', result[:icao] # lower-cased on output
    assert_equal 'N123456', result[:registration]
    assert_equal '123456', result[:serial_number]
    assert_equal 2023, result[:manufacture_year]
    assert_equal '2023-06-23', result[:registration_date]
    assert_equal 'american_airlines', result[:owner]
    assert_equal 'active', result[:status] # enum label, default 0
    assert_equal 2, result[:engine_count]
    assert_equal 'CFM56-7B27', result[:engine_model]
    assert_equal 'B737', result[:type][:type_code]
    assert_equal 'American Airlines', result[:operator][:name]
    assert_equal 'United States', result[:registration_country][:name]
  end

  test 'leaves a nil operator as nil' do
    aircraft_record = aircraft(:one)
    aircraft_record.operator = nil

    result = Enrichment::AircraftSerializer.call(aircraft_record)

    assert_nil result[:operator]
  end

  test 'emits a nil registration_date as nil' do
    aircraft_record = aircraft(:one)
    aircraft_record.registration_date = nil

    result = Enrichment::AircraftSerializer.call(aircraft_record)

    assert_nil result[:registration_date]
  end
end
```

> Note: the `owner` value `american_airlines` comes from the fixture (`test/fixtures/aircraft.yml`), which stores the fixture label string in the `owner` column. The serializer returns the column value verbatim.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/aircraft_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::AircraftSerializer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/aircraft_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an Aircraft into the v2.enrich.aircraft response body's `aircraft`
  # object. The ICAO Mode-S hex is lower-cased on output for consistency with the
  # flight-tracking pipeline; `status` is the enum label; `registration_date` is
  # an ISO 8601 date string. The opt-in provenance block is added by the handler,
  # not here.
  class AircraftSerializer
    # @param aircraft [Aircraft]
    # @return [Hash]
    def self.call(aircraft)
      {
        icao: aircraft.icao&.downcase,
        registration: aircraft.registration,
        serial_number: aircraft.serial_number,
        manufacture_year: aircraft.manufacture_year,
        registration_date: aircraft.registration_date&.iso8601,
        owner: aircraft.owner,
        status: aircraft.status,
        model: aircraft.model,
        name: aircraft.aircraft_name,
        engine_count: aircraft.engine_count,
        engine_model: aircraft.engine_model,
        cabin_configuration: aircraft.cabin_configuration,
        type: AircraftTypeSerializer.call(aircraft.aircraft_type),
        operator: OperatorSerializer.call(aircraft.operator),
        registration_country: CountrySerializer.call(aircraft.registration_country)
      }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/aircraft_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/aircraft_serializer.rb test/services/enrichment/aircraft_serializer_test.rb
git commit -m "feat(enrichment): add aircraft serializer"
```

---

## Task 8: Airport serializer

**Files:**
- Create: `app/services/enrichment/airport_serializer.rb`
- Test: `test/services/enrichment/airport_serializer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/airport_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportSerializerTest < ActiveSupport::TestCase
  test 'serialises an airport with country, FIR and runways' do
    result = Enrichment::AirportSerializer.call(airports(:yssy))

    assert_equal 'YSSY', result[:icao_code]
    assert_equal 'SYD', result[:iata_code]
    assert_equal '94719', result[:wmo_code]
    assert_equal 'Sydney International Airport', result[:name]
    assert_equal 'Sydney', result[:city]
    assert_in_delta(-33.946111, result[:latitude], 0.000001)
    assert_in_delta 13.0, result[:altitude], 0.001
    assert_equal 'Australia/Sydney', result[:timezone]
    assert_equal 'Australia', result[:country][:name]
    assert_equal({ icao_code: 'YMMM', region: 'Melbourne' }, result[:flight_information_region])

    runway_names = result[:runways].map { |r| r[:name] }
    assert_includes runway_names, '16R'
    assert_includes runway_names, '25'
  end

  test 'emits a nil flight information region as nil' do
    airport = airports(:yssy)
    airport.flight_information_region = nil

    result = Enrichment::AirportSerializer.call(airport)

    assert_nil result[:flight_information_region]
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/airport_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::AirportSerializer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/airport_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises an Airport into the v2.enrich.airport response body's `airport`
  # object, including its runways and (shallow) flight information region. The
  # opt-in provenance block is added by the handler, not here.
  class AirportSerializer
    # @param airport [Airport]
    # @return [Hash]
    def self.call(airport)
      {
        icao_code: airport.icao_code,
        iata_code: airport.iata_code,
        wmo_code: airport.wmo_code,
        name: airport.name,
        city: airport.city,
        latitude: airport.latitude&.to_f,
        longitude: airport.longitude&.to_f,
        altitude: airport.altitude&.to_f,
        timezone: airport.timezone,
        country: CountrySerializer.call(airport.country),
        flight_information_region: FlightInformationRegionSerializer.call(airport.flight_information_region),
        runways: airport.airport_runways.map { |runway| RunwaySerializer.call(runway) }
      }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/airport_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/airport_serializer.rb test/services/enrichment/airport_serializer_test.rb
git commit -m "feat(enrichment): add airport serializer"
```

---

## Task 9: Route serializer

**Files:**
- Create: `app/services/enrichment/route_serializer.rb`
- Test: `test/services/enrichment/route_serializer_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/route_serializer_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::RouteSerializerTest < ActiveSupport::TestCase
  test 'serialises a route with operator and ordered segments' do
    result = Enrichment::RouteSerializer.call(routes(:aa_1))

    assert_equal 'AA1', result[:callsign]
    assert_equal 'American Airlines', result[:operator][:name]
    assert_equal 2, result[:segments].length

    first = result[:segments].first
    assert_equal 1, first[:order]
    assert_equal '00:15:04', first[:departing_time]
    assert_equal '00:15:04', first[:arrival_time]
    assert_equal 'YSSY', first[:airport][:icao_code]
    assert_not first[:airport].key?(:runways) # uses the lean summary
  end

  test 'orders segments by their order column' do
    result = Enrichment::RouteSerializer.call(routes(:aa_1))

    orders = result[:segments].map { |segment| segment[:order] }
    assert_equal orders.sort, orders
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/route_serializer_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::RouteSerializer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/route_serializer.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Serialises a Route into the v2.enrich.route response body's `route` object.
  # Segments are ordered by their `order` column and embed the lean
  # airport_summary (no runways) plus the scheduled times. Times are formatted as
  # HH:MM:SS strings (the underlying column is a time-of-day, not a full datetime).
  class RouteSerializer
    TIME_FORMAT = '%H:%M:%S'

    # @param route [Route]
    # @return [Hash]
    def self.call(route)
      {
        callsign: route.call_sign,
        operator: OperatorSerializer.call(route.operator),
        segments: route.route_segments.sort_by(&:order).map { |segment| segment_hash(segment) }
      }
    end

    # @param segment [RouteSegment]
    # @return [Hash]
    def self.segment_hash(segment)
      {
        order: segment.order,
        departing_time: segment.departing_time&.strftime(TIME_FORMAT),
        arrival_time: segment.arrival_time&.strftime(TIME_FORMAT),
        airport: AirportSummarySerializer.call(segment.airport)
      }
    end
    private_class_method :segment_hash
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/route_serializer_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/route_serializer.rb test/services/enrichment/route_serializer_test.rb
git commit -m "feat(enrichment): add route serializer"
```

---

## Task 10: Query objects

**Files:**
- Create: `app/services/enrichment/aircraft_query.rb`
- Create: `app/services/enrichment/route_query.rb`
- Create: `app/services/enrichment/airport_query.rb`
- Test: `test/services/enrichment/aircraft_query_test.rb`
- Test: `test/services/enrichment/route_query_test.rb`
- Test: `test/services/enrichment/airport_query_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/services/enrichment/aircraft_query_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftQueryTest < ActiveSupport::TestCase
  test 'finds an aircraft by ICAO case-insensitively' do
    expected = aircraft(:one)

    assert_equal expected, Enrichment::AircraftQuery.call(expected.icao.downcase)
    assert_equal expected, Enrichment::AircraftQuery.call(expected.icao.upcase)
  end

  test 'returns nil for an unknown ICAO' do
    assert_nil Enrichment::AircraftQuery.call('ZZZZZZ')
  end

  test 'returns nil for a blank ICAO' do
    assert_nil Enrichment::AircraftQuery.call('')
    assert_nil Enrichment::AircraftQuery.call(nil)
  end
end
```

`test/services/enrichment/route_query_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::RouteQueryTest < ActiveSupport::TestCase
  test 'finds a route by callsign case-insensitively' do
    expected = routes(:aa_1)

    assert_equal expected, Enrichment::RouteQuery.call('aa1')
    assert_equal expected, Enrichment::RouteQuery.call('AA1')
  end

  test 'returns nil for an unknown callsign' do
    assert_nil Enrichment::RouteQuery.call('ZZ999')
  end

  test 'returns nil for a blank callsign' do
    assert_nil Enrichment::RouteQuery.call(nil)
  end
end
```

`test/services/enrichment/airport_query_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportQueryTest < ActiveSupport::TestCase
  test 'finds an airport by ICAO case-insensitively' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(icao: 'yssy')
    assert_equal expected, Enrichment::AirportQuery.call(icao: 'YSSY')
  end

  test 'finds an airport by IATA case-insensitively' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(iata: 'syd')
  end

  test 'prefers ICAO when both are given' do
    expected = airports(:yssy)

    assert_equal expected, Enrichment::AirportQuery.call(icao: 'YSSY', iata: 'NOPE')
  end

  test 'returns nil when neither ICAO nor IATA is given' do
    assert_nil Enrichment::AirportQuery.call(icao: nil, iata: nil)
  end

  test 'returns nil for an unknown code' do
    assert_nil Enrichment::AirportQuery.call(icao: 'ZZZZ')
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/enrichment/aircraft_query_test.rb test/services/enrichment/route_query_test.rb test/services/enrichment/airport_query_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::AircraftQuery`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/aircraft_query.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Looks up a single Aircraft by ICAO Mode-S hex, case-insensitively, eager
  # loading every association the aircraft serializer touches to avoid N+1
  # queries.
  class AircraftQuery
    # @param icao [String, nil]
    # @return [Aircraft, nil]
    def self.call(icao)
      return nil if icao.blank?

      Aircraft
        .includes(
          :registration_country,
          { operator: %i[country parent_operator] },
          { aircraft_type: { manufacturer: :country } }
        )
        .where('UPPER(icao) = ?', icao.to_s.upcase)
        .first
    end
  end
end
```

`app/services/enrichment/route_query.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Looks up a single Route by callsign, case-insensitively, eager loading the
  # operator and the ordered segments with their airports for the route
  # serializer.
  class RouteQuery
    # @param callsign [String, nil]
    # @return [Route, nil]
    def self.call(callsign)
      return nil if callsign.blank?

      Route
        .includes(
          { operator: %i[country parent_operator] },
          { route_segments: { airport: :country } }
        )
        .where('UPPER(call_sign) = ?', callsign.to_s.upcase)
        .first
    end
  end
end
```

`app/services/enrichment/airport_query.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Looks up a single Airport by ICAO or IATA code, case-insensitively. ICAO
  # takes precedence when both are supplied. Eager loads the country, flight
  # information region and runways for the airport serializer.
  class AirportQuery
    # @param icao [String, nil]
    # @param iata [String, nil]
    # @return [Airport, nil]
    def self.call(icao: nil, iata: nil)
      scope = Airport.includes(:country, :flight_information_region, :airport_runways)

      if icao.present?
        scope.where('UPPER(icao_code) = ?', icao.to_s.upcase).first
      elsif iata.present?
        scope.where('UPPER(iata_code) = ?', iata.to_s.upcase).first
      end
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/enrichment/aircraft_query_test.rb test/services/enrichment/route_query_test.rb test/services/enrichment/airport_query_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/aircraft_query.rb app/services/enrichment/route_query.rb app/services/enrichment/airport_query.rb test/services/enrichment/aircraft_query_test.rb test/services/enrichment/route_query_test.rb test/services/enrichment/airport_query_test.rb
git commit -m "feat(enrichment): add aircraft, route and airport query objects"
```

---

## Task 11: Errors and request parser

**Files:**
- Create: `app/services/enrichment/errors.rb`
- Create: `app/services/enrichment/request_parser.rb`
- Test: `test/services/enrichment/request_parser_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/request_parser_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::RequestParserTest < ActiveSupport::TestCase
  test 'parses a JSON object into a symbolised hash' do
    result = Enrichment::RequestParser.parse('{"icao":"7C1469","include":["provenance"]}')

    assert_equal '7C1469', result[:icao]
    assert_equal ['provenance'], result[:include]
  end

  test 'raises BadRequestError for malformed JSON' do
    assert_raises(Enrichment::BadRequestError) do
      Enrichment::RequestParser.parse('{not json')
    end
  end

  test 'raises BadRequestError for a blank payload' do
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('') }
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse(nil) }
  end

  test 'raises BadRequestError when the payload is not a JSON object' do
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('"just a string"') }
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('[1,2,3]') }
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/request_parser_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::RequestParser`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/errors.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Raised when an incoming request payload is malformed or missing required
  # fields. Handlers translate this into a `bad_request` reply rather than an
  # internal error.
  class BadRequestError < StandardError; end
end
```

`app/services/enrichment/request_parser.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Parses a raw NATS message payload (a JSON object) into a symbolised hash.
  # Every enrichment request is a JSON object; anything else is a bad request.
  class RequestParser
    # @param data [String, nil] The raw message payload.
    # @return [Hash] The parsed request with symbolised keys.
    # @raise [BadRequestError] If the payload is blank, not valid JSON, or not an object.
    def self.parse(data)
      raise BadRequestError, 'empty request payload' if data.nil? || data.empty?

      parsed = JSON.parse(data)
      raise BadRequestError, 'request must be a JSON object' unless parsed.is_a?(Hash)

      parsed.deep_symbolize_keys
    rescue JSON::ParserError => e
      raise BadRequestError, "invalid JSON: #{e.message}"
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/request_parser_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/errors.rb app/services/enrichment/request_parser.rb test/services/enrichment/request_parser_test.rb
git commit -m "feat(enrichment): add request parser and error type"
```

---

## Task 12: Handler base class

**Files:**
- Create: `app/services/enrichment/handler.rb`
- Test: `test/services/enrichment/handler_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/handler_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::HandlerTest < ActiveSupport::TestCase
  # A minimal concrete handler used to exercise the base-class behaviour.
  class EchoHandler < Enrichment::Handler
    private

    def handle(request)
      raise Enrichment::BadRequestError, 'boom' if request[:fail] == 'bad'
      raise 'kaboom' if request[:fail] == 'internal'

      { found: true, echo: request[:value], provenance_requested: include?(request, 'provenance') }
    end
  end

  test 'parses, dispatches to handle, and returns a JSON string' do
    reply = EchoHandler.new.call('{"value":"hi"}')

    assert_equal({ 'found' => true, 'echo' => 'hi', 'provenance_requested' => false }, JSON.parse(reply))
  end

  test 'include? reflects the include array' do
    reply = EchoHandler.new.call('{"value":"hi","include":["provenance"]}')

    assert_equal true, JSON.parse(reply)['provenance_requested']
  end

  test 'translates BadRequestError into a bad_request reply' do
    reply = EchoHandler.new.call('{"fail":"bad"}')

    assert_equal({ 'error' => 'boom', 'code' => 'bad_request' }, JSON.parse(reply))
  end

  test 'translates malformed JSON into a bad_request reply' do
    reply = EchoHandler.new.call('{not json')

    assert_equal 'bad_request', JSON.parse(reply)['code']
  end

  test 'translates an unexpected error into an internal reply and logs it' do
    reply = EchoHandler.new.call('{"fail":"internal"}')

    assert_equal({ 'error' => 'internal', 'code' => 'internal' }, JSON.parse(reply))
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/handler_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::Handler`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/handler.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Base class for per-subject request handlers. Owns the request lifecycle:
  # parse the payload, dispatch to the subclass's #handle, and serialise the
  # result to a JSON string. Translates known and unknown failures into the
  # standard error replies so the service always returns a well-formed body.
  #
  # Subclasses implement #handle(request) and return a Ruby hash.
  class Handler
    # @param data [String, nil] The raw NATS message payload.
    # @return [String] The JSON reply body.
    def call(data)
      request = RequestParser.parse(data)
      handle(request).to_json
    rescue BadRequestError => e
      { error: e.message, code: 'bad_request' }.to_json
    rescue StandardError => e
      Rails.logger.error("[enrichment] #{self.class.name} failed: #{e.class}: #{e.message}")
      { error: 'internal', code: 'internal' }.to_json
    end

    private

    # @param request [Hash] The parsed, symbolised request.
    # @return [Hash] The response body to serialise.
    def handle(_request)
      raise NotImplementedError, "#{self.class.name} must implement #handle"
    end

    # Returns true when the request opted into the named extra (e.g. 'provenance').
    #
    # @param request [Hash]
    # @param key [String]
    # @return [Boolean]
    def include?(request, key)
      Array(request[:include]).map(&:to_s).include?(key.to_s)
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/handler_test.rb`
Expected: PASS (0 failures). The internal-error test also logs a line; that is expected.

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/handler.rb test/services/enrichment/handler_test.rb
git commit -m "feat(enrichment): add request handler base class"
```

---

## Task 13: Aircraft, Route and Airport handlers

**Files:**
- Create: `app/services/enrichment/aircraft_handler.rb`
- Create: `app/services/enrichment/route_handler.rb`
- Create: `app/services/enrichment/airport_handler.rb`
- Test: `test/services/enrichment/aircraft_handler_test.rb`
- Test: `test/services/enrichment/route_handler_test.rb`
- Test: `test/services/enrichment/airport_handler_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/services/enrichment/aircraft_handler_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AircraftHandlerTest < ActiveSupport::TestCase
  test 'returns found aircraft for a known ICAO' do
    reply = JSON.parse(Enrichment::AircraftHandler.new.call({ icao: aircraft(:one).icao }.to_json))

    assert_equal true, reply['found']
    assert_equal aircraft(:one).icao.downcase, reply['aircraft']['icao']
    assert_not reply.key?('provenance')
  end

  test 'returns found:false for an unknown ICAO' do
    reply = JSON.parse(Enrichment::AircraftHandler.new.call({ icao: 'ZZZZZZ' }.to_json))

    assert_equal({ 'found' => false }, reply)
  end

  test 'includes provenance when requested' do
    record = aircraft(:one)
    record.update_column(:field_provenance, { 'owner' => { 'source_type' => 'AutoGenerated', 'confidence' => 50 } })

    reply = JSON.parse(Enrichment::AircraftHandler.new.call({ icao: record.icao, include: ['provenance'] }.to_json))

    assert reply.key?('provenance')
    assert_equal 50, reply['provenance']['owner']['confidence']
  end

  test 'returns bad_request when ICAO is missing' do
    reply = JSON.parse(Enrichment::AircraftHandler.new.call({}.to_json))

    assert_equal 'bad_request', reply['code']
  end
end
```

`test/services/enrichment/route_handler_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::RouteHandlerTest < ActiveSupport::TestCase
  test 'returns found route for a known callsign' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({ callsign: 'AA1' }.to_json))

    assert_equal true, reply['found']
    assert_equal 'AA1', reply['route']['callsign']
  end

  test 'returns found:false for an unknown callsign' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({ callsign: 'ZZ999' }.to_json))

    assert_equal({ 'found' => false }, reply)
  end

  test 'returns bad_request when callsign is missing' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({}.to_json))

    assert_equal 'bad_request', reply['code']
  end
end
```

`test/services/enrichment/airport_handler_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportHandlerTest < ActiveSupport::TestCase
  test 'returns found airport for a known ICAO' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ icao: 'YSSY' }.to_json))

    assert_equal true, reply['found']
    assert_equal 'YSSY', reply['airport']['icao_code']
    assert reply['airport']['runways'].any?
  end

  test 'returns found airport for a known IATA' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ iata: 'SYD' }.to_json))

    assert_equal 'YSSY', reply['airport']['icao_code']
  end

  test 'returns found:false for an unknown code' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ icao: 'ZZZZ' }.to_json))

    assert_equal({ 'found' => false }, reply)
  end

  test 'returns bad_request when neither ICAO nor IATA is given' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({}.to_json))

    assert_equal 'bad_request', reply['code']
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/enrichment/aircraft_handler_test.rb test/services/enrichment/route_handler_test.rb test/services/enrichment/airport_handler_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::AircraftHandler`.

- [ ] **Step 3: Write the implementations**

`app/services/enrichment/aircraft_handler.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.aircraft: looks up an aircraft by ICAO Mode-S hex and
  # returns its serialised record, optionally with a provenance block.
  class AircraftHandler < Handler
    private

    def handle(request)
      icao = request[:icao]
      raise BadRequestError, 'icao is required' if icao.blank?

      aircraft = AircraftQuery.call(icao)
      return { found: false } unless aircraft

      response = { found: true, aircraft: AircraftSerializer.call(aircraft) }
      response[:provenance] = ProvenanceSerializer.call(aircraft) if include?(request, 'provenance')
      response
    end
  end
end
```

`app/services/enrichment/route_handler.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.route: looks up a route by callsign and returns its
  # serialised record. Routes do not carry field-level provenance, so the
  # provenance include is not honoured here.
  class RouteHandler < Handler
    private

    def handle(request)
      callsign = request[:callsign]
      raise BadRequestError, 'callsign is required' if callsign.blank?

      route = RouteQuery.call(callsign)
      return { found: false } unless route

      { found: true, route: RouteSerializer.call(route) }
    end
  end
end
```

`app/services/enrichment/airport_handler.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Handles v2.enrich.airport: looks up an airport by ICAO or IATA code and
  # returns its serialised record (including runways), optionally with a
  # provenance block.
  class AirportHandler < Handler
    private

    def handle(request)
      icao = request[:icao]
      iata = request[:iata]
      raise BadRequestError, 'icao or iata is required' if icao.blank? && iata.blank?

      airport = AirportQuery.call(icao: icao, iata: iata)
      return { found: false } unless airport

      response = { found: true, airport: AirportSerializer.call(airport) }
      response[:provenance] = ProvenanceSerializer.call(airport) if include?(request, 'provenance')
      response
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/enrichment/aircraft_handler_test.rb test/services/enrichment/route_handler_test.rb test/services/enrichment/airport_handler_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/aircraft_handler.rb app/services/enrichment/route_handler.rb app/services/enrichment/airport_handler.rb test/services/enrichment/aircraft_handler_test.rb test/services/enrichment/route_handler_test.rb test/services/enrichment/airport_handler_test.rb
git commit -m "feat(enrichment): add aircraft, route and airport handlers"
```

---

## Task 14: Dispatcher

**Files:**
- Create: `app/services/enrichment/dispatcher.rb`
- Test: `test/services/enrichment/dispatcher_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/dispatcher_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::DispatcherTest < ActiveSupport::TestCase
  setup { @dispatcher = Enrichment::Dispatcher.new }

  test 'routes a known subject to its handler' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.aircraft', { icao: aircraft(:one).icao }.to_json))

    assert_equal true, reply['found']
  end

  test 'routes the airport subject to its handler' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.airport', { icao: 'YSSY' }.to_json))

    assert_equal 'YSSY', reply['airport']['icao_code']
  end

  test 'returns a bad_request reply for an unsupported subject' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.unknown', '{}'))

    assert_equal 'bad_request', reply['code']
    assert_match(/unsupported subject/, reply['error'])
  end

  test 'exposes the set of supported subjects' do
    assert_equal %w[v2.enrich.aircraft v2.enrich.route v2.enrich.airport].sort,
                 Enrichment::Dispatcher::SUBJECTS.keys.sort
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/dispatcher_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::Dispatcher`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/dispatcher.rb`:

```ruby
# frozen_string_literal: true

module Enrichment
  # Maps an exact NATS subject to its handler instance. The NATS server
  # subscribes to the `v2.enrich.*` wildcard, so messages for unknown subjects
  # under that wildcard reach the dispatcher and receive a bad_request reply
  # rather than timing out.
  class Dispatcher
    # Subject string => handler class.
    SUBJECTS = {
      'v2.enrich.aircraft' => AircraftHandler,
      'v2.enrich.route' => RouteHandler,
      'v2.enrich.airport' => AirportHandler
    }.freeze

    def initialize
      @handlers = SUBJECTS.transform_values(&:new)
    end

    # @param subject [String] The exact NATS subject of the message.
    # @param data [String, nil] The raw message payload.
    # @return [String] The JSON reply body.
    def dispatch(subject, data)
      handler = @handlers[subject]
      return unsupported(subject) unless handler

      handler.call(data)
    end

    private

    def unsupported(subject)
      { error: "unsupported subject: #{subject}", code: 'bad_request' }.to_json
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/dispatcher_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/dispatcher.rb test/services/enrichment/dispatcher_test.rb
git commit -m "feat(enrichment): add subject dispatcher"
```

---

## Task 15: Metrics

**Files:**
- Create: `app/services/enrichment/metrics.rb`
- Test: `test/services/enrichment/metrics_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/metrics_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::MetricsTest < ActiveSupport::TestCase
  test 'records a request observation against the counter and histogram' do
    before = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })

    Enrichment::Metrics.observe(subject: 'v2.enrich.aircraft', result: 'hit', duration: 0.01)

    after = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    assert_equal before + 1, after
  end

  test 'classify maps a reply body to a result label' do
    assert_equal 'hit', Enrichment::Metrics.classify('{"found":true}')
    assert_equal 'miss', Enrichment::Metrics.classify('{"found":false}')
    assert_equal 'bad_request', Enrichment::Metrics.classify('{"code":"bad_request"}')
    assert_equal 'error', Enrichment::Metrics.classify('{"code":"internal"}')
  end

  test 'increment_reconnects bumps the reconnect counter' do
    before = Enrichment::Metrics.reconnects.get
    Enrichment::Metrics.increment_reconnects
    assert_equal before + 1, Enrichment::Metrics.reconnects.get
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/metrics_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::Metrics`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/metrics.rb`:

```ruby
# frozen_string_literal: true

require 'prometheus/client'

module Enrichment
  # Prometheus instrumentation for the enrichment service. Metrics are registered
  # lazily against a dedicated registry (memoised) so the definitions are created
  # exactly once per process. The runner process is single-OS-process, so a plain
  # registry is sufficient (no multiprocess directory needed).
  module Metrics
    module_function

    # The metric label applied to successful lookups.
    RESULT_HIT = 'hit'
    # The metric label applied to lookup misses.
    RESULT_MISS = 'miss'
    # The metric label applied to malformed/invalid requests.
    RESULT_BAD_REQUEST = 'bad_request'
    # The metric label applied to internal failures.
    RESULT_ERROR = 'error'

    # Histogram buckets in seconds, tuned for fast indexed DB lookups.
    DURATION_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1].freeze

    def registry
      @registry ||= Prometheus::Client::Registry.new
    end

    def requests
      @requests ||= registry.counter(
        :aerodex_enrichment_requests_total,
        docstring: 'Total enrichment requests handled, by subject and result.',
        labels: %i[subject result]
      )
    end

    def request_duration
      @request_duration ||= registry.histogram(
        :aerodex_enrichment_request_duration_seconds,
        docstring: 'Enrichment request handler duration in seconds, by subject.',
        labels: %i[subject],
        buckets: DURATION_BUCKETS
      )
    end

    def reconnects
      @reconnects ||= registry.counter(
        :aerodex_enrichment_nats_reconnects_total,
        docstring: 'Total NATS reconnects observed by the enrichment service.'
      )
    end

    def in_flight
      @in_flight ||= registry.gauge(
        :aerodex_enrichment_in_flight,
        docstring: 'Enrichment requests currently being processed, by subject.',
        labels: %i[subject]
      )
    end

    # Records a completed request.
    #
    # @param subject [String]
    # @param result [String] One of the RESULT_* labels.
    # @param duration [Float] Handler duration in seconds.
    def observe(subject:, result:, duration:)
      requests.increment(labels: { subject: subject, result: result })
      request_duration.observe(duration, labels: { subject: subject })
    end

    # Increments the reconnect counter.
    def increment_reconnects
      reconnects.increment
    end

    # Derives the result label from a JSON reply body. Falls back to 'error' for
    # anything unparseable.
    #
    # @param reply [String] The JSON reply body.
    # @return [String] One of the RESULT_* labels.
    def classify(reply)
      parsed = JSON.parse(reply)
      case parsed['code']
      when 'bad_request' then RESULT_BAD_REQUEST
      when 'internal' then RESULT_ERROR
      else
        parsed['found'] == true ? RESULT_HIT : RESULT_MISS
      end
    rescue JSON::ParserError
      RESULT_ERROR
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/metrics_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/metrics.rb test/services/enrichment/metrics_test.rb
git commit -m "feat(enrichment): add Prometheus metrics"
```

---

## Task 16: Metrics HTTP server

**Files:**
- Create: `app/services/enrichment/metrics_server.rb`
- Test: `test/services/enrichment/metrics_server_test.rb`

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/metrics_server_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'net/http'

class Enrichment::MetricsServerTest < ActiveSupport::TestCase
  test 'serves the Prometheus text exposition on /metrics' do
    # Record at least one observation so the output is non-empty.
    Enrichment::Metrics.observe(subject: 'v2.enrich.aircraft', result: 'hit', duration: 0.01)

    server = Enrichment::MetricsServer.new(port: 0) # port 0 = OS-assigned free port
    server.start
    begin
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{server.port}/metrics"))

      assert_equal '200', response.code
      assert_match(/aerodex_enrichment_requests_total/, response.body)
    ensure
      server.stop
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/metrics_server_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::MetricsServer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/metrics_server.rb`:

```ruby
# frozen_string_literal: true

require 'webrick'
require 'prometheus/client/formats/text'

module Enrichment
  # A minimal HTTP server that exposes the enrichment service's Prometheus
  # metrics on /metrics. Runs WEBrick in a background thread so the main thread
  # stays free for the NATS subscription loop. Mirrors how the Go pw_atc_api
  # service exposed its own metrics port.
  class MetricsServer
    # Content type for the Prometheus text exposition format (version 0.0.4).
    CONTENT_TYPE = 'text/plain; version=0.0.4'
    # Default port; matches the Go service's monitoring port for consistency.
    DEFAULT_PORT = 9602

    # @param port [Integer] The port to listen on (0 selects a free OS port).
    def initialize(port: ENV.fetch('METRICS_PORT', DEFAULT_PORT).to_i)
      @configured_port = port
    end

    # Starts the server in a background thread. Returns once it is accepting
    # connections.
    def start
      @server = WEBrick::HTTPServer.new(
        Port: @configured_port,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      @server.mount_proc('/metrics') do |_request, response|
        response.content_type = CONTENT_TYPE
        response.body = Prometheus::Client::Formats::Text.marshal(Metrics.registry)
      end
      @thread = Thread.new { @server.start }
    end

    # The actual port the server bound to (useful when port 0 was requested).
    #
    # @return [Integer]
    def port
      @server.config[:Port]
    end

    # Stops the server and joins its thread.
    def stop
      @server&.shutdown
      @thread&.join
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/metrics_server_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/metrics_server.rb test/services/enrichment/metrics_server_test.rb
git commit -m "feat(enrichment): add Prometheus metrics HTTP server"
```

---

## Task 17: NATS server

**Files:**
- Create: `app/services/enrichment/nats_server.rb`
- Test: `test/services/enrichment/nats_server_test.rb`

This task covers the message-handling logic that does not require a live NATS connection (subject wiring, executor wrap, metrics). The end-to-end connection is exercised in Task 19.

- [ ] **Step 1: Write the failing test**

`test/services/enrichment/nats_server_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class Enrichment::NatsServerTest < ActiveSupport::TestCase
  # A stand-in for a nats-pure message: captures whatever the server responds.
  class FakeMessage
    attr_reader :subject, :data, :reply, :responses

    def initialize(subject:, data:, reply: '_INBOX.test')
      @subject = subject
      @data = data
      @reply = reply
      @responses = []
    end

    def respond(payload)
      @responses << payload
    end
  end

  setup { @server = Enrichment::NatsServer.new(url: 'nats://unused.invalid:4222') }

  test 'handle_message dispatches and responds with the serialised reply' do
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json)

    @server.send(:handle_message, message)

    assert_equal 1, message.responses.length
    assert_equal true, JSON.parse(message.responses.first)['found']
  end

  test 'handle_message records a hit metric' do
    before = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json)

    @server.send(:handle_message, message)

    after = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    assert_equal before + 1, after
  end

  test 'handle_message does not respond when there is no reply inbox' do
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json, reply: nil)

    @server.send(:handle_message, message)

    assert_empty message.responses
  end

  test 'subscribes to the v2.enrich wildcard under the default queue group' do
    assert_equal 'v2.enrich.*', Enrichment::NatsServer::SUBJECT_WILDCARD
    assert_equal 'aerodex-enrich-v2', Enrichment::NatsServer::DEFAULT_QUEUE_GROUP
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/enrichment/nats_server_test.rb`
Expected: FAIL with `NameError: uninitialized constant Enrichment::NatsServer`.

- [ ] **Step 3: Write the implementation**

`app/services/enrichment/nats_server.rb`:

```ruby
# frozen_string_literal: true

require 'nats/client'

module Enrichment
  # The long-lived NATS consumer for the enrichment service. Connects to NATS,
  # subscribes to the v2.enrich.* wildcard under a queue group (so work is
  # load-balanced across replicas), and dispatches each message to a handler.
  #
  # Each message is processed inside Rails.application.executor.wrap so that the
  # ActiveRecord connection used by the handler is checked out from, and returned
  # to, the connection pool correctly — essential because handlers run on
  # nats-pure's callback thread pool.
  #
  # Lifecycle: #run connects, subscribes, starts the metrics server, then blocks
  # until a SIGTERM/SIGINT triggers a graceful drain.
  class NatsServer
    # The wildcard subject covering every v2 enrichment subject.
    SUBJECT_WILDCARD = 'v2.enrich.*'
    # The queue group; all replicas share it so each request is handled once.
    DEFAULT_QUEUE_GROUP = 'aerodex-enrich-v2'

    # @param url [String, nil] The NATS server URL (defaults to NATS_URL).
    # @param queue_group [String] The queue group name.
    # @param metrics_server [MetricsServer] The metrics exposition server.
    def initialize(
      url: ENV.fetch('NATS_URL', nil),
      queue_group: ENV.fetch('NATS_QUEUE_GROUP', DEFAULT_QUEUE_GROUP),
      metrics_server: MetricsServer.new
    )
      @url = url
      @queue_group = queue_group
      @metrics_server = metrics_server
      @dispatcher = Dispatcher.new
      @stop = Queue.new
    end

    # Connects, subscribes and blocks until signalled to shut down, then drains.
    def run
      connect
      subscribe
      @metrics_server.start
      install_signal_traps
      Rails.logger.info(
        "[enrichment] subscribed to #{SUBJECT_WILDCARD} (queue=#{@queue_group}); waiting for requests"
      )
      @stop.pop # block until a signal pushes onto the stop queue
      shutdown
    end

    private

    def connect
      @nats = NATS.connect(@url)
      @nats.on_reconnect { Metrics.increment_reconnects }
      @nats.on_error { |error| Rails.logger.error("[enrichment] NATS error: #{error.class}: #{error.message}") }
    end

    def subscribe
      @subscription = @nats.subscribe(SUBJECT_WILDCARD, queue: @queue_group) do |msg|
        handle_message(msg)
      end
    end

    # Processes a single message: dispatch, respond, and record metrics. Wrapped
    # in the Rails executor for correct connection and reloader handling.
    #
    # @param msg [#subject, #data, #reply, #respond]
    def handle_message(msg)
      Rails.application.executor.wrap do
        Metrics.in_flight.increment(labels: { subject: msg.subject })
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        reply = @dispatcher.dispatch(msg.subject, msg.data)
        msg.respond(reply) if msg.reply

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        Metrics.observe(subject: msg.subject, result: Metrics.classify(reply), duration: duration)
      ensure
        Metrics.in_flight.decrement(labels: { subject: msg.subject })
      end
    rescue StandardError => e
      # A failure here means the executor or metrics raised, not a handler error
      # (handlers rescue internally). Log and continue serving.
      Rails.logger.error("[enrichment] message handling failed: #{e.class}: #{e.message}")
    end

    def install_signal_traps
      %w[TERM INT].each do |signal|
        Signal.trap(signal) { @stop.push(signal) }
      end
    end

    # Drains the subscription so in-flight requests finish and their replies are
    # flushed, then stops the metrics server.
    def shutdown
      Rails.logger.info('[enrichment] draining NATS connection')
      @nats&.drain
      @metrics_server.stop
      Rails.logger.info('[enrichment] shut down cleanly')
    end
  end
end
```

> Note on `ensure` inside a block: Ruby 2.6+ allows `begin`-less `ensure` directly in a `do...end` block body, which is what `handle_message` relies on. The outer `rescue` on the method catches anything raised by the executor wrap itself.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/enrichment/nats_server_test.rb`
Expected: PASS (0 failures). Note: these tests never open a real socket — they drive `handle_message` directly with a fake message.

- [ ] **Step 5: Commit**

```bash
git add app/services/enrichment/nats_server.rb test/services/enrichment/nats_server_test.rb
git commit -m "feat(enrichment): add NATS server with executor wrap and metrics"
```

---

## Task 18: Executable and process wiring

**Files:**
- Create: `bin/enrichment-server`
- Modify: `Procfile.dev`

- [ ] **Step 1: Write the executable**

`bin/enrichment-server`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Entry point for the NATS enrichment service. Boots the full Rails environment
# (eager loaded) so ActiveRecord models are available, then runs the long-lived
# NATS consumer. Run as its own process type, separate from the Puma web server.
#
# Configuration (environment variables):
#   NATS_URL          NATS server URL, e.g. nats://user:pass@host:4222 (required)
#   NATS_QUEUE_GROUP  Queue group name (default: aerodex-enrich-v2)
#   METRICS_PORT      Prometheus metrics port (default: 9602)

require_relative '../config/environment'

# Eager load so every model and service is loaded before we start serving,
# rather than autoloading lazily on the callback threads.
Rails.application.eager_load!

Enrichment::NatsServer.new.run
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/enrichment-server`
Expected: no output; `ls -l bin/enrichment-server` shows the executable bit.

- [ ] **Step 3: Verify it boots and fails fast without a NATS server**

Run: `NATS_URL=nats://127.0.0.1:4222 timeout 20 bin/enrichment-server; echo "exit: $?"`
Expected: with no NATS server running it raises a connection error from `NATS.connect` and exits non-zero (e.g. `Errno::ECONNREFUSED`). This confirms the Rails environment boots and the code path is reached. (If a NATS server *is* running locally, it will instead log the "subscribed" line and run until the 20s timeout.)

- [ ] **Step 4: Add a development process entry**

Add this line to `Procfile.dev` (so `bin/dev` can optionally run it alongside web/js/css):

```
enrich: NATS_URL=${NATS_URL:-nats://127.0.0.1:4222} bin/enrichment-server
```

> Note: `bin/dev` runs every Procfile.dev entry. If you do not have a local NATS server, comment this line out or run the enrichment server separately with `bin/enrichment-server`. Production/Kamal declares this as its own role using the same image with the command overridden to `bin/enrichment-server`; no Dockerfile change is required because the runtime image already contains the full app and gems.

- [ ] **Step 5: Commit**

```bash
git add bin/enrichment-server Procfile.dev
git commit -m "feat(enrichment): add enrichment-server executable and dev process entry"
```

---

## Task 19: End-to-end integration test (skipped without a NATS server)

**Files:**
- Test: `test/integration/enrichment/nats_round_trip_test.rb`

- [ ] **Step 1: Write the integration test**

`test/integration/enrichment/nats_round_trip_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'nats/client'

# Proves the full NATS request/reply path end to end against a real nats-server.
# Skipped unless NATS_TEST_URL is set, so the default suite (and CI without a
# broker) stays green. To run it locally:
#   1. Start a broker:  nats-server
#   2. NATS_TEST_URL=nats://127.0.0.1:4222 bin/rails test test/integration/enrichment/nats_round_trip_test.rb
class Enrichment::NatsRoundTripTest < ActiveSupport::TestCase
  setup do
    @url = ENV.fetch('NATS_TEST_URL', nil)
    skip 'set NATS_TEST_URL to run the NATS integration test' if @url.blank?

    # Subscribe directly (no queue group needed for a single responder in the test)
    # and reuse the dispatcher so we exercise the real subject routing.
    @responder = NATS.connect(@url)
    @dispatcher = Enrichment::Dispatcher.new
    @subscription = @responder.subscribe('v2.enrich.*') do |msg|
      Rails.application.executor.wrap { msg.respond(@dispatcher.dispatch(msg.subject, msg.data)) }
    end
    @responder.flush

    @client = NATS.connect(@url)
  end

  teardown do
    @subscription&.unsubscribe
    @responder&.close
    @client&.close
  end

  test 'request/reply returns the serialised aircraft' do
    response = @client.request('v2.enrich.aircraft', { icao: aircraft(:one).icao }.to_json, timeout: 2)
    body = JSON.parse(response.data)

    assert_equal true, body['found']
    assert_equal aircraft(:one).icao.downcase, body['aircraft']['icao']
  end

  test 'request/reply returns found:false for an unknown aircraft' do
    response = @client.request('v2.enrich.aircraft', { icao: 'ZZZZZZ' }.to_json, timeout: 2)

    assert_equal({ 'found' => false }, JSON.parse(response.data))
  end
end
```

- [ ] **Step 2: Run it (skips without a broker)**

Run: `bin/rails test test/integration/enrichment/nats_round_trip_test.rb`
Expected: the two tests are reported as **skipped** (no `NATS_TEST_URL`), suite green.

- [ ] **Step 3: Optionally run it against a real broker**

If `nats-server` is available locally:

Run: `nats-server &` then `NATS_TEST_URL=nats://127.0.0.1:4222 bin/rails test test/integration/enrichment/nats_round_trip_test.rb`
Expected: PASS (2 runs, 0 failures). Stop the broker afterwards: `kill %1`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/enrichment/nats_round_trip_test.rb
git commit -m "test(enrichment): add NATS round-trip integration test"
```

---

## Task 20: Full suite, documentation and final commit

**Files:**
- Modify: `README.md`
- Create: `docs/nats-enrichment.md`

- [ ] **Step 1: Run the full enrichment suite**

Run: `bin/rails test test/services/enrichment test/integration/enrichment`
Expected: all enrichment tests PASS (integration tests skipped without a broker), 0 failures, 0 errors.

- [ ] **Step 2: Run the entire test suite to confirm no regressions**

Run: `bin/rails test`
Expected: the full suite passes (same pass/fail baseline as before this work, plus the new enrichment tests).

- [ ] **Step 3: Run RuboCop on the new files**

Run: `bundle exec rubocop app/services/enrichment bin/enrichment-server test/services/enrichment test/integration/enrichment`
Expected: no offences (fix any that appear before continuing).

- [ ] **Step 4: Write the feature documentation**

`docs/nats-enrichment.md`:

````markdown
# NATS Enrichment Service

Aerodex serves its aviation reference data over NATS so the flight-tracking
pipeline can enrich a live ADS-B stream without replicating aerodex's database.
The service is a dedicated, long-lived consumer process — separate from the Puma
web server — that answers NATS request-reply RPCs.

It exposes a new, aerodex-owned `v2.enrich.*` subject set. It does not replace the
existing Go `pw_atc_api` service; the two run side by side.

## Running

```bash
NATS_URL=nats://user:pass@host:4222 bin/enrichment-server
```

Configuration (environment variables):

| Variable           | Default              | Purpose                                  |
|--------------------|----------------------|------------------------------------------|
| `NATS_URL`         | (required)           | NATS server URL.                         |
| `NATS_QUEUE_GROUP` | `aerodex-enrich-v2`  | Queue group; replicas share it.          |
| `METRICS_PORT`     | `9602`               | Prometheus `/metrics` HTTP port.         |

Scale by running more replicas: every replica joins the same queue group, so NATS
load-balances requests across them.

## Subjects and contract

All requests are a small JSON object; all responses are JSON with `snake_case`
keys and an explicit `found` boolean. A miss returns `{ "found": false }`.

### `v2.enrich.aircraft`

Request: `{ "icao": "7C1469", "include": ["provenance"] }` (`include` optional).

Returns the aircraft with nested `type`, `operator` and `registration_country`.
With `"include": ["provenance"]`, a top-level `provenance` block reports the
source and confidence for each tracked field.

### `v2.enrich.route`

Request: `{ "callsign": "QFA123" }`.

Returns the route with its `operator` and ordered `segments`; each segment embeds
a lean airport summary (no runways) and the scheduled times.

### `v2.enrich.airport`

Request: `{ "icao": "YPPH" }` or `{ "iata": "PER" }` (ICAO takes precedence).

Returns the airport with its `country`, `flight_information_region` and full
`runways`. Supports the `provenance` include.

### Errors

| Situation                         | Reply                                            |
|-----------------------------------|--------------------------------------------------|
| Miss                              | `{ "found": false }`                             |
| Malformed request / missing key   | `{ "error": "...", "code": "bad_request" }`      |
| Unexpected internal error         | `{ "error": "internal", "code": "internal" }`    |

The service always replies; it never lets a caller time out on an internal error.

## Metrics

Prometheus metrics are exposed on `METRICS_PORT` at `/metrics`:

- `aerodex_enrichment_requests_total{subject, result}` — `result` is `hit`,
  `miss`, `bad_request` or `error`.
- `aerodex_enrichment_request_duration_seconds{subject}` — handler latency.
- `aerodex_enrichment_nats_reconnects_total` — NATS reconnects.
- `aerodex_enrichment_in_flight{subject}` — requests currently being processed.

## Shutdown

On `SIGTERM`/`SIGINT` the process drains the NATS subscription: it stops
accepting new messages, lets in-flight requests finish and flushes their replies,
then exits. Give the orchestrator a termination grace period longer than the NATS
drain timeout (30s default).

## Design

See `docs/superpowers/specs/2026-05-28-nats-enrichment-design.md` for the full
design rationale.
````

- [ ] **Step 5: Update the README**

Add a "NATS Enrichment Service" entry to `README.md`. Locate the architecture/overview section and add a short paragraph plus a link. Use this exact text, placed after the existing architecture description:

```markdown
### NATS Enrichment Service

Aerodex can serve its reference data over a NATS message bus for the
flight-tracking pipeline, via a dedicated consumer process (`bin/enrichment-server`)
that answers `v2.enrich.*` request-reply RPCs for aircraft, routes and airports.
See [doc/nats-enrichment](docs/nats-enrichment.md) for details.
```

> If the README has no clear architecture section, add the block above under a new top-level `## NATS Enrichment Service` heading near the end, before any licence section.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/nats-enrichment.md
git commit -m "docs(enrichment): document the NATS enrichment service"
```

- [ ] **Step 7: Push the branch**

Run: `git push`
Expected: the `feature/nats-enrichment-service` branch updates on the remote.

---

## Self-Review

**Spec coverage:**

| Spec section | Implemented by |
|---|---|
| `v2.enrich.aircraft` | Tasks 7, 10, 13, 14 |
| `v2.enrich.route` | Tasks 9, 10, 13, 14 |
| `v2.enrich.airport` (ICAO + IATA) | Tasks 8, 10, 13, 14 |
| Shared `country` object | Task 2 |
| `manufacturer` (full coverage) | Task 3 |
| `operator` (full coverage + shallow parent) | Task 3 |
| `aircraft_type` | Task 4 |
| `runway` (unit-less decimals → floats) | Task 5 |
| `airport_summary` (no runways in routes) | Task 5, used in Task 9 |
| Explicit `found` flag / miss = `{found:false}` | Tasks 12, 13 |
| JSON request envelope + opt-in `include: [provenance]` | Tasks 11, 12, 13 |
| Provenance block via `all_provenance_with_sources` | Task 6 |
| Always-reply error conventions (`bad_request`, `internal`) | Tasks 12, 14 |
| Dedicated `bin/enrichment-server` process | Task 18 |
| Executor wrap + DB-pool correctness | Task 17 |
| Queue group / horizontal scale | Tasks 17, 18, 20 |
| Prometheus metrics (4 metrics) + exposition | Tasks 15, 16 |
| Graceful drain on SIGTERM | Task 17 |
| Structured logging | Tasks 12, 17 |
| Testing strategy (queries, serializers, handlers, integration) | Tasks 2–17, 19 |
| Dependencies (`nats-pure`, `prometheus-client`) | Task 1 |
| Documentation | Task 20 |

No spec requirement is left without a task.

**Type/name consistency check:**
- Serializers are all `self.call(...)` returning `Hash`/`nil`. ✓
- Handlers subclass `Enrichment::Handler`, implement private `#handle(request)`, use `include?(request, 'provenance')`. ✓
- `Dispatcher::SUBJECTS` keys (`v2.enrich.aircraft|route|airport`) match the handler classes and the `NatsServer` wildcard `v2.enrich.*`. ✓
- `Metrics.classify` returns the same labels (`hit`/`miss`/`bad_request`/`error`) that `observe` records and that the metrics test asserts. ✓
- `MetricsServer#port` is used by its own test (port 0 path) and is consistent with `DEFAULT_PORT`/`METRICS_PORT`. ✓
- Query method shapes: `AircraftQuery.call(icao)`, `RouteQuery.call(callsign)`, `AirportQuery.call(icao:, iata:)` — match every handler call site. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — every code step contains complete code. ✓
