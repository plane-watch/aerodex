# VRS GitHub Route Importer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import airline route and route-segment data from the VRS `vradarserver/standing-data` GitHub repository into Aerodex's `Route`/`RouteSegment` models, resolving operators and airports against the existing database.

**Architecture:** Two-stage processor pipeline. Stage 1 (`Processors::Route::VRS`) fetches route CSVs from GitHub and upserts raw rows into a new `route_sources` table. Stage 2 (`Processors::Route::Route#combine_sources`) resolves each source row's airline and airport codes against existing `Operator`/`Airport` records and stages `Route` records — each carrying its `RouteSegment` children as nested attributes — through the existing `StagedBatch` review system.

**Tech Stack:** Ruby on Rails 8, PostgreSQL, Excon (HTTP, mockable in tests), Minitest with fixtures, Meilisearch (search indexing via existing hooks).

**Spec:** `docs/superpowers/specs/2026-05-30-vrs-github-route-importer-design.md`

**Branch:** `feature/vrs-github-route-importer` (do not commit to `develop`).

---

## File Structure

**Create:**
- `db/migrate/<ts>_create_route_sources.rb` — new `route_sources` STI table.
- `db/migrate/<ts>_add_unique_index_to_routes.rb` — unique index on `routes (operator_id, call_sign)`.
- `app/models/source/route/route_source.rb` — abstract base source model.
- `app/models/source/route/vrs_route_source.rb` — VRS STI subclass.
- `app/models/processors/route/vrs.rb` — Stage 1 import processor.
- `app/models/processors/route/route.rb` — Stage 2 combine processor.
- `app/models/source/route/` test files and processor test files (paths below).
- `doc/processors/route_importer.md` — feature documentation.

**Modify:**
- `app/models/route.rb` — nested attributes, uniqueness validation, `dependent: :destroy`.
- `app/controllers/admin/processors_controller.rb` — add `Route` to `PROCESSOR_ENTITY_TYPES`.
- `test/fixtures/operators.yml`, `test/fixtures/airports.yml` — add fixtures the combine tests resolve against.
- `README.md` — list the route data source.

**Conventions to follow (verified in the codebase):**
- Source tables use single-table inheritance with a `type` column and a `(natural_key, type)` unique index; raw imports `upsert_all` into them.
- Raw import processors are invoked from the console/methods (no rake wiring); only the combine `Processors::<Entity>::<Entity>` gets rake/admin/job wiring via naming convention.
- Tests mock HTTP with `Excon.stub`; `Processors::Base.get_source_from_url` enables Excon mock mode automatically under `Rails.env == 'test'`.
- Australian/British English in comments and strings. Comments use articles ("the", "a"). No magic numbers/strings — use named constants.

---

## Task 1: Migration — create `route_sources` table

**Files:**
- Create: `db/migrate/<ts>_create_route_sources.rb`

- [ ] **Step 1: Generate the migration file**

Run:
```bash
./bin/rails generate migration CreateRouteSources
```
Expected: creates `db/migrate/<timestamp>_create_route_sources.rb`.

- [ ] **Step 2: Write the migration**

Replace the generated file's contents with:

```ruby
# frozen_string_literal: true

# Creates the route_sources table for storing raw airline route data from
# external sources before combining into canonical Route and RouteSegment records.
#
# This follows the same single-table-inheritance pattern as operator_sources,
# aircraft_sources, etc. The VRS GitHub importer stores its raw rows here.
class CreateRouteSources < ActiveRecord::Migration[8.0]
  def change
    create_table :route_sources do |t|
      # STI column for the source type (e.g. Source::Route::VRSRouteSource).
      t.string :type, null: false

      # The full normalised callsign, e.g. "QFA1". The natural key for upserts.
      t.string :callsign, null: false

      # The code used to look up the owning airline, e.g. "QFA".
      t.string :airline_code, null: false

      # A hyphen-separated list of airport codes in flight order, e.g. "YSSY-WSSS-EGLL".
      t.string :airport_codes, null: false

      # Flexible storage for source-specific fields (retains VRS Code and Number).
      t.jsonb :data, null: false, default: {}

      # The timestamp of the import batch that produced this record.
      t.datetime :import_date, null: false

      # Exclusion fields (mirrors the other source tables; see HasSourceExclusion).
      t.boolean :excluded, default: false, null: false
      t.string :exclusion_reason
      t.datetime :excluded_at
      t.string :excluded_by

      t.timestamps
    end

    add_index :route_sources, [:callsign, :type], unique: true
    add_index :route_sources, :airline_code
    add_index :route_sources, :excluded
    add_index :route_sources, :data, using: :gin
  end
end
```

- [ ] **Step 3: Run the migration**

Run:
```bash
./bin/rails db:migrate
```
Expected: `create_table(:route_sources)` runs successfully; `db/schema.rb` updated with the `route_sources` table.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "$(cat <<'EOF'
feat(routes): add route_sources table

Adds the STI source table for storing raw airline route data before
combining into canonical Route/RouteSegment records.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Migration — unique index on `routes (operator_id, call_sign)`

A route's identity is its operator plus callsign. This index makes re-runs idempotent and backs the uniqueness validation added in Task 4.

**Files:**
- Create: `db/migrate/<ts>_add_unique_index_to_routes.rb`

- [ ] **Step 1: Generate the migration**

Run:
```bash
./bin/rails generate migration AddUniqueIndexToRoutes
```

- [ ] **Step 2: Write the migration**

Replace the generated file's contents with:

```ruby
# frozen_string_literal: true

# Adds a unique index on routes (operator_id, call_sign).
#
# A route is uniquely identified by its operator and callsign. This index
# gives routes a natural identity, making combine re-runs idempotent and
# backing the uniqueness validation on the Route model.
class AddUniqueIndexToRoutes < ActiveRecord::Migration[8.0]
  def change
    add_index :routes, [:operator_id, :call_sign],
              unique: true,
              name: 'index_routes_on_operator_id_and_call_sign'
  end
end
```

- [ ] **Step 3: Run the migration**

Run:
```bash
./bin/rails db:migrate
```
Expected: index created. If it fails with a uniqueness violation, the development database holds duplicate `(operator_id, call_sign)` routes that must be de-duplicated first — report this rather than forcing the index.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "$(cat <<'EOF'
feat(routes): add unique index on routes (operator_id, call_sign)

Gives routes a natural identity for idempotent combine re-runs.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Source models — `RouteSource` and `VRSRouteSource`

**Files:**
- Create: `app/models/source/route/route_source.rb`
- Create: `app/models/source/route/vrs_route_source.rb`
- Test: `test/models/source/route/route_source_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/source/route/route_source_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

module Source
  module Route
    class RouteSourceTest < ActiveSupport::TestCase
      def build_source(attrs = {})
        Source::Route::VRSRouteSource.new(
          {
            callsign: 'QFA1',
            airline_code: 'QFA',
            airport_codes: 'YSSY-WSSS-EGLL',
            import_date: Time.current
          }.merge(attrs)
        )
      end

      test 'is valid with the required fields' do
        assert build_source.valid?
      end

      test 'requires callsign, airline_code, airport_codes and import_date' do
        source = build_source(callsign: nil, airline_code: nil, airport_codes: nil, import_date: nil)
        assert_not source.valid?
        assert_includes source.errors.attribute_names, :callsign
        assert_includes source.errors.attribute_names, :airline_code
        assert_includes source.errors.attribute_names, :airport_codes
        assert_includes source.errors.attribute_names, :import_date
      end

      test 'airport_code_list splits the hyphenated airport codes in order' do
        assert_equal %w[YSSY WSSS EGLL], build_source.airport_code_list
      end

      test 'includable scope excludes flagged records' do
        included = build_source(callsign: 'QFA10')
        included.save!
        excluded = build_source(callsign: 'QFA20')
        excluded.save!
        excluded.exclude!(reason: 'test')

        callsigns = Source::Route::VRSRouteSource.includable.pluck(:callsign)
        assert_includes callsigns, 'QFA10'
        assert_not_includes callsigns, 'QFA20'
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
./bin/rails test test/models/source/route/route_source_test.rb
```
Expected: FAIL with an uninitialised constant `Source::Route::VRSRouteSource`.

- [ ] **Step 3: Write the base source model**

Create `app/models/source/route/route_source.rb`:

```ruby
# frozen_string_literal: true

module Source
  module Route
    # Base class for route source records.
    #
    # Route sources store raw airline route data from external providers before
    # combining into canonical Route and RouteSegment records. Subclasses use
    # single-table inheritance via the `type` column.
    class RouteSource < ApplicationRecord
      include HasSourceExclusion

      self.table_name = 'route_sources'

      validates :callsign, presence: true
      validates :airline_code, presence: true
      validates :airport_codes, presence: true
      validates :import_date, presence: true

      # Splits the raw hyphenated airport codes into an ordered array.
      #
      # @return [Array<String>] The airport codes in flight order, e.g. %w[YSSY WSSS EGLL]
      def airport_code_list
        airport_codes.to_s.split('-')
      end
    end
  end
end
```

- [ ] **Step 4: Write the VRS subclass**

Create `app/models/source/route/vrs_route_source.rb`:

```ruby
# frozen_string_literal: true

module Source
  module Route
    # Source records for airline routes from the VRS (Virtual Radar Server)
    # standing-data GitHub repository.
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/routes/schema-01
    class VRSRouteSource < RouteSource
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
./bin/rails test test/models/source/route/route_source_test.rb
```
Expected: PASS (4 runs, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add app/models/source/route test/models/source/route
git commit -m "$(cat <<'EOF'
feat(routes): add Route source models

Adds Source::Route::RouteSource (abstract base) and VRSRouteSource (STI
subclass) for storing raw VRS route data.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `Route` model changes — nested attributes, uniqueness, dependent destroy

**Files:**
- Modify: `app/models/route.rb`
- Test: `test/models/route_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/route_test.rb` (if a `route_test.rb` already exists, add these tests to it instead):

```ruby
# frozen_string_literal: true

require 'test_helper'

class RouteTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:american_airlines)
    @yssy = airports(:yssy)
    @klax = airports(:klax)
  end

  test 'call_sign is unique within an operator' do
    Route.create!(operator: @operator, call_sign: 'AA999')
    duplicate = Route.new(operator: @operator, call_sign: 'AA999')
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :call_sign
  end

  test 'accepts nested route_segments attributes and maintains order' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA998',
      route_segments_attributes: [
        { airport_id: @yssy.id, order: 0 },
        { airport_id: @klax.id, order: 1 }
      ]
    )

    ordered = route.route_segments.order(:order)
    assert_equal [@yssy.id, @klax.id], ordered.map(&:airport_id)
    assert_equal 2, route.reload.route_segments_count
  end

  test 'replacing segments via nested attributes destroys the old ones' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA997',
      route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
    )
    old_segment_id = route.route_segments.first.id

    route.update!(
      route_segments_attributes: [
        { id: old_segment_id, _destroy: true },
        { airport_id: @klax.id, order: 0 }
      ]
    )

    assert_nil RouteSegment.find_by(id: old_segment_id)
    assert_equal [@klax.id], route.reload.route_segments.map(&:airport_id)
    assert_equal 1, route.route_segments_count
  end

  test 'destroying a route destroys its segments' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA996',
      route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
    )
    segment_id = route.route_segments.first.id

    route.destroy!

    assert_nil RouteSegment.find_by(id: segment_id)
  end
end
```

- [ ] **Step 2: Add the `klax` airport fixture (needed by the test)**

Append to `test/fixtures/airports.yml`:

```yaml
klax:
  name: Los Angeles International Airport
  city: Los Angeles
  country: united_states
  iata_code: LAX
  icao_code: KLAX
  latitude: 33.942536
  longitude: -118.408075
  altitude: 125
  timezone: America/Los_Angeles
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
./bin/rails test test/models/route_test.rb
```
Expected: FAIL — uniqueness not enforced and/or `route_segments_attributes` not permitted (`ActiveRecord::AssociationNotFoundError` or unknown attribute).

- [ ] **Step 4: Modify the Route model**

In `app/models/route.rb`, change the associations and add the validation. Replace:

```ruby
  has_many :route_segments
  belongs_to :operator
```

with:

```ruby
  has_many :route_segments, dependent: :destroy
  belongs_to :operator

  # Allows the combine processor to stage a route together with its segments as
  # a single nested-attributes payload, applied atomically via the staged batch.
  accepts_nested_attributes_for :route_segments, allow_destroy: true

  # A route is uniquely identified by its operator and callsign.
  validates :call_sign, uniqueness: { scope: :operator_id }
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
./bin/rails test test/models/route_test.rb
```
Expected: PASS (4 runs, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add app/models/route.rb test/models/route_test.rb test/fixtures/airports.yml
git commit -m "$(cat <<'EOF'
feat(routes): support nested segments, uniqueness and dependent destroy

Adds accepts_nested_attributes_for :route_segments (allow_destroy), a
call_sign uniqueness validation scoped to operator, and dependent: :destroy
so applying a staged route writes its segments atomically.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Stage 1 — import processor `Processors::Route::VRS`

**Files:**
- Create: `app/models/processors/route/vrs.rb`
- Test: `test/processor/route/vrs_test.rb`

This task implements the raw GitHub → `route_sources` import. Tests drive parsing directly (no IO) and the fetch path via `Excon.stub`, matching `test/processor/vrs_data_operator_processor_test.rb`.

- [ ] **Step 1: Write the failing test for CSV parsing**

Create `test/processor/route/vrs_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

module Processors
  module Route
    class VrsTest < ActiveSupport::TestCase
      CSV_DATA = <<~CSV
        Callsign,Code,Number,AirlineCode,AirportCodes
        QFA1,QFA,1,QFA,YSSY-WSSS-EGLL
        QFA10,QFA,10,QFA,EGLL-YPPH
      CSV

      setup do
        Source::Route::VRSRouteSource.delete_all
      end

      test 'import_csv_data upserts rows into the source table' do
        Processors::Route::VRS.import_csv_data(CSV_DATA, source_name: 'QFA-all.csv')

        assert_equal 2, Source::Route::VRSRouteSource.count

        qfa1 = Source::Route::VRSRouteSource.find_by(callsign: 'QFA1')
        assert_equal 'QFA', qfa1.airline_code
        assert_equal 'YSSY-WSSS-EGLL', qfa1.airport_codes
        assert_equal '1', qfa1.data['Number']
        assert_equal 'QFA', qfa1.data['Code']
      end

      test 'import_csv_data strips a UTF-8 BOM from the header' do
        bom = "\xEF\xBB\xBF".dup.force_encoding('UTF-8')
        Processors::Route::VRS.import_csv_data(bom + CSV_DATA, source_name: 'bom.csv')

        assert_equal 2, Source::Route::VRSRouteSource.count
        assert Source::Route::VRSRouteSource.exists?(callsign: 'QFA1')
      end

      test 'import_csv_data is idempotent on re-import' do
        2.times { Processors::Route::VRS.import_csv_data(CSV_DATA, source_name: 'QFA-all.csv') }
        assert_equal 2, Source::Route::VRSRouteSource.count
      end

      test 'import_csv_data skips rows missing required fields' do
        bad = "Callsign,Code,Number,AirlineCode,AirportCodes\n,,,,\n"
        result = Processors::Route::VRS.import_csv_data(bad, source_name: 'bad.csv')

        assert_equal 0, Source::Route::VRSRouteSource.count
        assert_equal 1, result[:error_count]
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
./bin/rails test test/processor/route/vrs_test.rb
```
Expected: FAIL with uninitialised constant `Processors::Route::VRS`.

- [ ] **Step 3: Write the import processor**

Create `app/models/processors/route/vrs.rb`:

```ruby
# frozen_string_literal: true

require 'csv'
require 'json'

module Processors
  module Route
    # Imports airline route data from the VRS (Virtual Radar Server)
    # standing-data GitHub repository into the route_sources table.
    #
    # The repository organises route CSV files under routes/schema-01/<LETTER>/,
    # one file per airline named "<CODE>-all.csv" (<=10,000 routes) or split into
    # "<CODE>-<digit>.csv" files for larger airlines.
    #
    # This processor stores the rows verbatim; it does NOT resolve airlines or
    # airports. The combine step (Processors::Route::Route) resolves those against
    # the existing database.
    #
    # @example Import a single airline from GitHub
    #   Processors::Route::VRS.import_airline('QFA')
    #
    # @example Import every airline from GitHub
    #   Processors::Route::VRS.import_all_from_github
    #
    # @see https://github.com/vradarserver/standing-data/tree/main/routes/schema-01
    class VRS < Processors::Base
      # Raw content base for per-airline files (folder per first letter of the code).
      GITHUB_RAW_BASE = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/routes/schema-01'

      # Raw content root of the repository, used to build URLs from API tree paths.
      GITHUB_RAW_ROOT = 'https://raw.githubusercontent.com/vradarserver/standing-data/main'

      # GitHub API endpoint listing the repository tree recursively.
      GITHUB_API_TREE = 'https://api.github.com/repos/vradarserver/standing-data/git/trees/main?recursive=1'

      # The STI type stored on every imported row.
      SOURCE_TYPE = 'Source::Route::VRSRouteSource'

      # The maximum split-file digit (files are named <CODE>-0.csv .. <CODE>-9.csv).
      MAX_SPLIT_DIGIT = 9

      # The number of records to accumulate before flushing to the database.
      BATCH_SIZE = 1000

      class << self
        # Imports all route CSV files from a local clone of the repository.
        #
        # @param directory_path [String] Path to the routes/schema-01 directory
        # @return [Hash] Combined import results
        def import(directory_path)
          raise ArgumentError, "Directory not found: #{directory_path}" unless File.directory?(directory_path)

          csv_files = Dir.glob(File.join(directory_path, '*', '*.csv')).sort
          raise ArgumentError, "No CSV files found in #{directory_path}" if csv_files.empty?

          results = with_bulk_import do
            csv_files.map do |path|
              import_csv_data(File.read(path, encoding: 'utf-8'), source_name: File.basename(path))
            end
          end

          finalise(results)
        end

        # Imports every route file discovered from the GitHub API tree.
        #
        # @param progress [Boolean] Whether to show a progress bar
        # @return [Hash] Combined import results
        def import_all_from_github(progress: true)
          paths = fetch_available_paths
          if paths.empty?
            Rails.logger.error 'Failed to discover route files from GitHub'
            return finalise([])
          end

          Rails.logger.info "Found #{paths.count} route files to import from VRS"
          progress_bar = progress ? create_progress_bar(paths.count) : nil

          results = with_bulk_import do
            paths.map do |path|
              body = get_source_from_url("#{GITHUB_RAW_ROOT}/#{path}")
              progress_bar&.increment!
              next if body.nil?

              import_csv_data(body, source_name: File.basename(path))
            end.compact
          end

          finalise(results)
        end

        # Imports a single airline's routes from GitHub.
        #
        # Tries the "<CODE>-all.csv" file first; if absent, tries the split files
        # "<CODE>-0.csv" .. "<CODE>-9.csv".
        #
        # @param code [String] The airline callsign code, e.g. "QFA"
        # @return [Hash] Combined import results
        def import_airline(code)
          code = code.to_s.strip.upcase
          letter = code[0]
          base = "#{GITHUB_RAW_BASE}/#{letter}"

          results = with_bulk_import do
            all_body = get_source_from_url("#{base}/#{code}-all.csv")
            if all_body
              [import_csv_data(all_body, source_name: "#{code}-all.csv")]
            else
              (0..MAX_SPLIT_DIGIT).filter_map do |digit|
                body = get_source_from_url("#{base}/#{code}-#{digit}.csv")
                import_csv_data(body, source_name: "#{code}-#{digit}.csv") if body
              end
            end
          end

          finalise(results)
        end

        # Parses raw CSV content and upserts the rows into the source table.
        #
        # @param csv_data [String] The raw CSV content
        # @param source_name [String] A name for logging (usually the file name)
        # @return [Hash] Results with :success_count, :error_count and :errors
        def import_csv_data(csv_data, source_name:)
          success_count = 0
          errors = []
          pending = []
          timestamp = Time.current

          csv = CSV.parse(strip_bom(csv_data), headers: true)

          csv.each do |row|
            attributes = build_attributes(row, timestamp)

            if attributes.nil?
              errors << { source: source_name, row: row.to_h, error: 'Missing required field' }
              next
            end

            pending << attributes
            success_count += 1

            if pending.size >= BATCH_SIZE
              flush(pending)
              pending = []
            end
          end

          flush(pending)

          { success_count: success_count, error_count: errors.count, errors: errors }
        rescue CSV::MalformedCSVError => e
          Rails.logger.error "CSV parsing error in #{source_name}: #{e.message}"
          { success_count: 0, error_count: 1, errors: [{ source: source_name, error: e.message }] }
        end

        # Discovers the route CSV file paths from the GitHub API tree.
        #
        # @return [Array<String>] Repository-relative paths to route CSV files
        def fetch_available_paths
          response = get_source_from_url(
            GITHUB_API_TREE, 'GET',
            { 'Accept' => 'application/vnd.github.v3+json', 'User-Agent' => 'Aerodex-Route-Importer' }
          )
          return [] if response.nil?

          tree = JSON.parse(response)
          pattern = %r{\Aroutes/schema-01/[A-Z]/[A-Z0-9]+-(all|\d)\.csv\z}i

          tree['tree'].filter_map { |item| item['path'] if item['path'].match?(pattern) }.sort
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse GitHub API response: #{e.message}"
          []
        end

        private

        # Builds an attribute hash for one CSV row, or nil if a required field is missing.
        #
        # @param row [CSV::Row] The CSV row
        # @param timestamp [Time] The import batch timestamp
        # @return [Hash, nil] Attributes for upsert, or nil to skip the row
        def build_attributes(row, timestamp)
          callsign = row['Callsign']&.strip
          airline_code = row['AirlineCode']&.strip
          airport_codes = row['AirportCodes']&.strip

          return nil if callsign.blank? || airline_code.blank? || airport_codes.blank?

          {
            type: SOURCE_TYPE,
            callsign: callsign,
            airline_code: airline_code,
            airport_codes: airport_codes,
            data: { 'Code' => row['Code']&.strip, 'Number' => row['Number']&.strip }.compact,
            import_date: timestamp
          }
        end

        # Upserts a batch of attribute hashes into the source table.
        #
        # @param records [Array<Hash>] The attribute hashes to upsert
        def flush(records)
          return if records.empty?

          now = Time.current
          rows = records.map { |r| r.merge(created_at: now, updated_at: now) }

          Source::Route::VRSRouteSource.upsert_all(
            rows,
            unique_by: %i[callsign type],
            update_only: %i[airline_code airport_codes data import_date]
          )
        end

        # Removes a leading UTF-8 byte-order mark, if present.
        #
        # @param data [String] The raw content
        # @return [String] The content without a leading BOM
        def strip_bom(data)
          data.dup.force_encoding('UTF-8').sub(/\A\xEF\xBB\xBF/u, '')
        end

        # Aggregates per-file results and records an import report.
        #
        # @param results [Array<Hash>] Per-file results
        # @return [Hash] Combined results
        def finalise(results)
          combined = results.compact.each_with_object({ success_count: 0, error_count: 0, errors: [] }) do |r, acc|
            acc[:success_count] += r[:success_count]
            acc[:error_count] += r[:error_count]
            acc[:errors].concat(r[:errors])
          end

          new_import_report(combined[:errors], combined[:success_count] + combined[:error_count])
          combined
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the parsing tests to verify they pass**

Run:
```bash
./bin/rails test test/processor/route/vrs_test.rb
```
Expected: PASS (4 runs, 0 failures).

- [ ] **Step 5: Add a failing test for the GitHub fetch path**

Append to `test/processor/route/vrs_test.rb` inside the `VrsTest` class:

```ruby
      test 'import_airline fetches the -all.csv file via Excon' do
        Excon.stub(
          { scheme: 'https', host: 'raw.githubusercontent.com',
            path: '/vradarserver/standing-data/main/routes/schema-01/Q/QFA-all.csv', port: 443 },
          { body: CSV_DATA, status: 200 }
        )

        Processors::Route::VRS.import_airline('QFA')

        assert_equal 2, Source::Route::VRSRouteSource.count
      ensure
        Excon.stubs.clear
      end
```

- [ ] **Step 6: Run the fetch test to verify it passes**

Run:
```bash
./bin/rails test test/processor/route/vrs_test.rb
```
Expected: PASS (5 runs, 0 failures). `Processors::Base.get_source_from_url` enables Excon mock mode under the test environment, so the stub is used.

- [ ] **Step 7: Commit**

```bash
git add app/models/processors/route/vrs.rb test/processor/route/vrs_test.rb
git commit -m "$(cat <<'EOF'
feat(routes): add VRS GitHub route import processor

Processors::Route::VRS fetches route CSVs from the vradarserver
standing-data repository and upserts raw rows into route_sources.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Stage 2 — combine processor `Processors::Route::Route`

**Files:**
- Create: `app/models/processors/route/route.rb`
- Test: `test/processor/route/route_test.rb`
- Modify: `test/fixtures/operators.yml`, `test/fixtures/airports.yml` (add Qantas + Australian airports the tests resolve against)

This is the core combine. It resolves each source row against existing operators/airports and stages `Route` records (with nested segments) through a `StagedBatch`.

- [ ] **Step 1: Add fixtures the combine tests resolve against**

Append to `test/fixtures/operators.yml`:

```yaml
qantas:
  name: Qantas
  country: australia
  icao_code: QFA
  iata_code: QF
```

Append to `test/fixtures/airports.yml`:

```yaml
wsss:
  name: Singapore Changi Airport
  city: Singapore
  country: australia
  iata_code: SIN
  icao_code: WSSS
  latitude: 1.359167
  longitude: 103.989441
  altitude: 22
  timezone: Asia/Singapore

egll:
  name: London Heathrow Airport
  city: London
  country: australia
  iata_code: LHR
  icao_code: EGLL
  latitude: 51.4775
  longitude: -0.461389
  altitude: 83
  timezone: Europe/London
```

(Note: `country: australia` is used only to satisfy the not-null `country_id`; it is irrelevant to route resolution, which matches on ICAO/IATA codes. The `yssy` airport already exists in the fixtures.)

- [ ] **Step 2: Write the failing test**

Create `test/processor/route/route_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

module Processors
  module Route
    class RouteTest < ActiveSupport::TestCase
      setup do
        Source::Route::VRSRouteSource.delete_all
        StagedBatch.delete_all
        @qantas = operators(:qantas)
        @yssy = airports(:yssy)
        @wsss = airports(:wsss)
        @egll = airports(:egll)
      end

      def create_source(attrs = {})
        Source::Route::VRSRouteSource.create!(
          {
            callsign: 'QFA1',
            airline_code: 'QFA',
            airport_codes: 'YSSY-WSSS-EGLL',
            import_date: Time.current
          }.merge(attrs)
        )
      end

      test 'stages a create for a resolvable new route' do
        create_source

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        change = batch.staged_changes.first
        assert_equal 'Route', change.record_type
        assert_equal 'create', change.operation
        assert_equal 'QFA1', change.record_identifier

        segments = change.new_values['route_segments_attributes']
        assert_equal [@yssy.id, @wsss.id, @egll.id], segments.map { |s| s['airport_id'] }
        assert_equal [0, 1, 2], segments.map { |s| s['order'] }
      end

      test 'applying the batch creates the route with ordered segments' do
        create_source
        batch = Processors::Route::Route.combine_sources

        batch.apply!(by: nil)

        route = ::Route.find_by(operator: @qantas, call_sign: 'QFA1')
        assert_not_nil route
        assert_equal [@yssy.id, @wsss.id, @egll.id],
                     route.route_segments.order(:order).map(&:airport_id)
      end

      test 'skips the route and stages nothing when the operator is unresolved' do
        create_source(airline_code: 'ZZZ')

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
      end

      test 'skips the whole route when any airport is unresolved' do
        create_source(airport_codes: 'YSSY-XXXX-EGLL')

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
      end

      test 'stages nothing for an unchanged existing route' do
        create_source
        existing = ::Route.create!(
          operator: @qantas, call_sign: 'QFA1',
          route_segments_attributes: [
            { airport_id: @yssy.id, order: 0 },
            { airport_id: @wsss.id, order: 1 },
            { airport_id: @egll.id, order: 2 }
          ]
        )
        assert existing.persisted?

        batch = Processors::Route::Route.combine_sources

        assert_equal 0, batch.staged_changes.count
        assert_equal 1, batch.summary['unchanged']
      end

      test 'stages an update that replaces segments when they differ' do
        create_source
        ::Route.create!(
          operator: @qantas, call_sign: 'QFA1',
          route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
        )

        batch = Processors::Route::Route.combine_sources

        assert_equal 1, batch.staged_changes.count
        change = batch.staged_changes.first
        assert_equal 'update', change.operation

        batch.apply!(by: nil)
        route = ::Route.find_by(operator: @qantas, call_sign: 'QFA1')
        assert_equal [@yssy.id, @wsss.id, @egll.id],
                     route.route_segments.order(:order).map(&:airport_id)
      end

      test 'airline_code scopes the run to a single airline' do
        create_source(callsign: 'QFA1', airline_code: 'QFA')
        create_source(callsign: 'AAL1', airline_code: 'AAL', airport_codes: 'YSSY-WSSS')

        batch = Processors::Route::Route.combine_sources(airline_code: 'QFA')

        assert_equal 1, batch.staged_changes.count
        assert_equal 'QFA1', batch.staged_changes.first.record_identifier
      end
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
./bin/rails test test/processor/route/route_test.rb
```
Expected: FAIL with uninitialised constant `Processors::Route::Route`.

- [ ] **Step 4: Write the combine processor**

Create `app/models/processors/route/route.rb`:

```ruby
# frozen_string_literal: true

module Processors
  module Route
    # Combines VRS route source records into canonical Route and RouteSegment
    # records.
    #
    # For each source row this processor resolves the airline code to an existing
    # Operator and each airport code to an existing Airport. It does NOT create
    # operators or airports; routes whose references cannot be resolved are skipped
    # and reported, then retried on the next run once the data catches up.
    #
    # Each route is staged as a single StagedChange carrying its RouteSegment
    # children as nested attributes, so the existing staged-batch apply path
    # writes the route and its segments atomically.
    #
    # @example Combine every airline's routes
    #   Processors::Route::Route.combine_sources
    #
    # @example Combine one airline (keeps the staged batch reviewable)
    #   Processors::Route::Route.combine_sources(airline_code: 'QFA')
    class Route < Processors::Base
      # The entity type recorded on the staged batch.
      ENTITY_TYPE = 'Route'

      # The model class staged changes target (the canonical, top-level Route).
      RECORD_TYPE = 'Route'

      class << self
        # Combines route sources into staged Route changes.
        #
        # @param triggered_by [User, nil] The user who triggered the run
        # @param airline_code [String, nil] Optional airline code to scope the run
        # @return [StagedBatch] The batch containing the staged changes
        def combine_sources(triggered_by: nil, airline_code: nil)
          with_staged_batch(entity_type: ENTITY_TYPE, triggered_by: triggered_by) do
            preload_reference_data

            scope = Source::Route::VRSRouteSource.includable
            scope = scope.where(airline_code: airline_code) if airline_code.present?

            errors = []
            progress_bar = create_progress_bar(scope.count)

            scope.find_each do |source|
              error = combine_one(source)
              errors << error if error
              progress_bar.increment!
            end

            current_batch.notes = "Skipped #{errors.count} routes (unresolved references)" if errors.any?
            record_errors(errors)
          end
        ensure
          clear_caches
        end

        private

        # Preloads operators, airports and existing routes into memory for fast lookup.
        def preload_reference_data
          @operators_by_icao = ::Operator.where.not(icao_code: nil).index_by(&:icao_code)
          @operators_by_iata = ::Operator.where.not(iata_code: nil).index_by(&:iata_code)
          @airports_by_icao = ::Airport.where.not(icao_code: nil).index_by(&:icao_code)
          @airports_by_iata = ::Airport.where.not(iata_code: nil).index_by(&:iata_code)
          @existing_routes = ::Route.includes(:route_segments).index_by { |r| [r.operator_id, r.call_sign] }
        end

        # Clears the preloaded caches after the run.
        def clear_caches
          @operators_by_icao = @operators_by_iata = nil
          @airports_by_icao = @airports_by_iata = nil
          @existing_routes = nil
        end

        # Resolves and stages a single source row.
        #
        # @param source [Source::Route::VRSRouteSource] The source row
        # @return [Hash, nil] An error hash if the route was skipped, otherwise nil
        def combine_one(source)
          operator = resolve_operator(source.airline_code)
          return skip(source, "operator not found: #{source.airline_code}") if operator.nil?

          airports = resolve_airports(source.airport_code_list)
          return skip(source, "unresolved airport in: #{source.airport_codes}") if airports.nil?

          desired_airport_ids = airports.map(&:id)
          existing = @existing_routes[[operator.id, source.callsign]]

          if existing.nil?
            stage_create(operator, source.callsign, desired_airport_ids)
          elsif segments_match?(existing, desired_airport_ids)
            current_batch.summary['unchanged'] += 1
          else
            stage_update(existing, desired_airport_ids)
          end

          nil
        end

        # Resolves an airline code to an Operator (ICAO first, then IATA).
        #
        # @param code [String] The airline code
        # @return [Operator, nil]
        def resolve_operator(code)
          @operators_by_icao[code] || @operators_by_iata[code]
        end

        # Resolves an ordered list of airport codes to Airport records.
        #
        # @param codes [Array<String>] The airport codes in flight order
        # @return [Array<Airport>, nil] The airports in order, or nil if any is unresolved
        def resolve_airports(codes)
          resolved = codes.map { |code| @airports_by_icao[code] || @airports_by_iata[code] }
          return nil if resolved.any?(&:nil?)

          resolved
        end

        # Checks whether an existing route's ordered segments match the desired airports.
        #
        # @param route [Route] The existing route
        # @param desired_airport_ids [Array<Integer>] The desired airport ids in order
        # @return [Boolean]
        def segments_match?(route, desired_airport_ids)
          route.route_segments.sort_by(&:order).map(&:airport_id) == desired_airport_ids
        end

        # Stages a create for a new route, carrying its segments as nested attributes.
        #
        # @param operator [Operator] The resolved operator
        # @param call_sign [String] The route callsign
        # @param airport_ids [Array<Integer>] The ordered airport ids
        def stage_create(operator, call_sign, airport_ids)
          diff = {
            'operator_id' => [nil, operator.id],
            'call_sign' => [nil, call_sign],
            'route_segments_attributes' => [nil, segment_rows(airport_ids)]
          }

          current_batch.staged_changes.create!(
            record_type: RECORD_TYPE,
            record_identifier: call_sign,
            operation: :create,
            diff: diff
          )
          current_batch.summary['created'] += 1
        end

        # Stages an update that destroys the existing segments and recreates them.
        #
        # @param route [Route] The existing route
        # @param airport_ids [Array<Integer>] The ordered airport ids
        def stage_update(route, airport_ids)
          destroy_rows = route.route_segments.map { |s| { 'id' => s.id, '_destroy' => true } }
          old_repr = route.route_segments.sort_by(&:order)
                          .map { |s| { 'id' => s.id, 'airport_id' => s.airport_id, 'order' => s.order } }

          diff = {
            'route_segments_attributes' => [old_repr, destroy_rows + segment_rows(airport_ids)]
          }

          current_batch.staged_changes.create!(
            record_type: RECORD_TYPE,
            record_id: route.id,
            record_identifier: route.call_sign,
            operation: :update,
            diff: diff
          )
          current_batch.summary['updated'] += 1
        end

        # Builds ordered nested-attribute rows for new segments.
        #
        # @param airport_ids [Array<Integer>] The ordered airport ids
        # @return [Array<Hash>]
        def segment_rows(airport_ids)
          airport_ids.each_with_index.map do |airport_id, index|
            { 'airport_id' => airport_id, 'order' => index }
          end
        end

        # Logs a skipped route and returns an error hash for the import report.
        #
        # @param source [Source::Route::VRSRouteSource] The skipped source row
        # @param message [String] The reason for skipping
        # @return [Hash]
        def skip(source, message)
          Rails.logger.info "Skipping route #{source.callsign}: #{message}"
          { callsign: source.callsign, airline_code: source.airline_code, error: message }
        end

        # Records skipped routes in an import report for visibility.
        #
        # @param errors [Array<Hash>] The collected skip errors
        def record_errors(errors)
          return if errors.empty?

          Source::SourceImportReport.create!(
            import_errors: errors,
            importer_type: name,
            records_processed: errors.count,
            success: true
          )
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
./bin/rails test test/processor/route/route_test.rb
```
Expected: PASS (7 runs, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add app/models/processors/route/route.rb test/processor/route/route_test.rb test/fixtures/operators.yml test/fixtures/airports.yml
git commit -m "$(cat <<'EOF'
feat(routes): add route combine processor

Processors::Route::Route resolves VRS route sources against existing
operators and airports, staging each route with its segments as nested
attributes. Routes with unresolved references are skipped and reported.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Register the combine in the admin UI and rake convention

**Files:**
- Modify: `app/controllers/admin/processors_controller.rb`
- Test: `test/controllers/admin/processors_controller_test.rb` (create if absent)

- [ ] **Step 1: Write the failing test**

Create `test/controllers/admin/processors_controller_test.rb` (if it already exists, add the test inside it):

```ruby
# frozen_string_literal: true

require 'test_helper'

module Admin
  class ProcessorsControllerTest < ActiveSupport::TestCase
    test 'Route is a known processor entity type' do
      assert_includes Admin::ProcessorsController::PROCESSOR_ENTITY_TYPES, 'Route'
    end

    test 'the Route combine processor class resolves' do
      assert_nothing_raised { 'Processors::Route::Route'.constantize }
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
./bin/rails test test/controllers/admin/processors_controller_test.rb
```
Expected: FAIL on the first assertion (`Route` not in `PROCESSOR_ENTITY_TYPES`).

- [ ] **Step 3: Add Route to the entity types**

In `app/controllers/admin/processors_controller.rb`, add `Route` to the `PROCESSOR_ENTITY_TYPES` array (keep alphabetical-ish order consistent with the existing list):

```ruby
    PROCESSOR_ENTITY_TYPES = %w[
      Aircraft
      AircraftType
      Airport
      Country
      Manufacturer
      Operator
      Route
      Runway
    ].freeze
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
./bin/rails test test/controllers/admin/processors_controller_test.rb
```
Expected: PASS (2 runs, 0 failures).

- [ ] **Step 5: Verify the rake convention resolves the processor**

Run:
```bash
./bin/rails 'processors:list'
```
Expected: the output includes `Route`. (The `processors:run[Route]` task resolves `Processors::Route::Route` by convention.)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/processors_controller.rb test/controllers/admin/processors_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(routes): register Route combine in the admin processor list

Adds Route to PROCESSOR_ENTITY_TYPES so the combine appears in the admin
UI and is runnable via rake processors:run[Route].

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Documentation

**Files:**
- Create: `doc/processors/route_importer.md`
- Modify: `README.md`

- [ ] **Step 1: Write the feature documentation**

Create `doc/processors/route_importer.md`:

```markdown
# VRS Route Importer

Imports airline route and route-segment data from the VRS
[`vradarserver/standing-data`](https://github.com/vradarserver/standing-data/tree/main/routes/schema-01)
GitHub repository.

The importer does not import airline or airport data. It resolves each route's
airline and airport codes against the operators and airports already in the
Aerodex database.

## Pipeline

Like the other data sources, routes use a two-stage pipeline.

### Stage 1 — Import (raw data into `route_sources`)

`Processors::Route::VRS` fetches route CSV files from GitHub and upserts the rows
verbatim into the `route_sources` table. Run it from the console:

```ruby
# Import every airline discovered from the GitHub API tree.
Processors::Route::VRS.import_all_from_github

# Import a single airline by its callsign code.
Processors::Route::VRS.import_airline('QFA')

# Import from a local clone of the repository's routes/schema-01 directory.
Processors::Route::VRS.import('/path/to/standing-data/routes/schema-01')
```

### Stage 2 — Combine (source rows into canonical routes)

`Processors::Route::Route#combine_sources` resolves each source row's airline code
to an `Operator` (by ICAO, then IATA) and each airport code to an `Airport`
(by ICAO, then IATA), then stages a `Route` — with its `RouteSegment` children as
nested attributes — into a `StagedBatch` for review.

A route is skipped (and recorded in a `SourceImportReport`) if its operator or any
of its airports cannot be resolved. Skipped routes are retried automatically on the
next combine once the missing operators/airports exist.

Run the combine via the admin Processors page, the rake task, or the console:

```bash
rake processors:run[Route]        # enqueues a background job
rake processors:run_sync[Route]   # runs synchronously
```

```ruby
# Scope a run to a single airline to keep the staged batch reviewable.
Processors::Route::Route.combine_sources(airline_code: 'QFA')
```

## Reviewing batches

An unscoped combine stages one change per route across all airlines, which can
produce a very large, impractical-to-review batch. When changes must be reviewed
manually, run the combine per airline with `airline_code:` so each batch contains
a single operator's routes.
```

- [ ] **Step 2: Update the README data-source listing**

In `README.md`, under the architecture/data-sources description, add a line noting that flight routes are imported from the VRS standing-data GitHub repository via `Processors::Route::VRS` (import) and `Processors::Route::Route` (combine). Match the surrounding prose style. If no explicit data-source list exists, add a short "Flight Routes" note to the architecture section pointing to `doc/processors/route_importer.md`.

- [ ] **Step 3: Commit**

```bash
git add doc/processors/route_importer.md README.md
git commit -m "$(cat <<'EOF'
docs(routes): document the VRS route importer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

- [ ] **Step 1: Run the full route-related test suite**

Run:
```bash
./bin/rails test test/models/source/route test/models/route_test.rb test/processor/route test/controllers/admin/processors_controller_test.rb
```
Expected: all tests PASS.

- [ ] **Step 2: Run the complete suite to check for regressions**

Run:
```bash
./bin/rails test
```
Expected: no new failures introduced by this work. Investigate any failure before considering the plan complete.

- [ ] **Step 3: Confirm the branch state**

Run:
```bash
git log --oneline develop..HEAD
git status
```
Expected: the commits from Tasks 1–8 are present on `feature/vrs-github-route-importer`, the working tree is clean, and nothing has been committed to `develop`.

---

## Notes on the design tradeoff (carried from the spec)

A full, unscoped combine stages one `StagedChange` per route — potentially 100,000+
in one batch. This was an explicit decision to keep routes consistent with the
existing per-record staging. The `airline_code:` argument is the escape hatch for
producing reviewable batches and is documented as the recommended approach for
manual review.
