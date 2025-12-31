# Aerodex Data Pipeline Architecture

This document describes the data pipeline architecture, including sources, processors, the provenance system, and the recommended order of operations for initial imports.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Layers](#2-architecture-layers)
3. [Source System](#3-source-system)
4. [Processor System](#4-processor-system)
5. [Trust & Provenance System](#5-trust--provenance-system)
6. [Import Order & Dependencies](#6-import-order--dependencies)
7. [Examples](#7-examples)
8. [Appendix: Source Trust Scores](#appendix-source-trust-scores)

---

## 1. Overview

Aerodex aggregates aviation data from multiple heterogeneous sources into a canonical data model. The pipeline follows a two-phase approach:

```
External Sources → [Import Phase] → Source Tables → [Combine Phase] → Canonical Tables
```

**Why this approach?**

1. **Separation of concerns**: Raw data ingestion is decoupled from data reconciliation
2. **Auditability**: Original source data is preserved for debugging and re-processing
3. **Flexibility**: New sources can be added without schema changes to canonical tables
4. **Trust-based resolution**: When sources conflict, the most trustworthy value wins

---

## 2. Architecture Layers

### 2.1 Directory Structure

```
app/
├── models/
│   ├── processors/           # ETL processors (import & combine)
│   │   ├── base.rb          # Base class with common utilities
│   │   ├── aircraft/        # Aircraft-specific processors
│   │   ├── aircraft_type/   # Aircraft type processors
│   │   ├── airport/         # Airport processors
│   │   ├── country/         # Country processors
│   │   ├── manufacturer/    # Manufacturer processors
│   │   ├── operator/        # Operator processors
│   │   └── runway/          # Runway processors
│   ├── source/              # Source record models (STI)
│   │   ├── aircraft/        # Aircraft source variants
│   │   ├── aircraft_type/   # Aircraft type source variants
│   │   ├── airport/         # Airport source variants
│   │   ├── country/         # Country source variants
│   │   ├── manufacturer/    # Manufacturer source variants
│   │   ├── operator/        # Operator source variants
│   │   └── runway/          # Runway source variants
│   ├── concerns/
│   │   ├── has_field_provenance.rb    # Field-level provenance tracking
│   │   ├── source_registry.rb         # Source metadata registry
│   │   └── manufacturer_normalisation.rb
│   └── source_config.rb     # Centralised trust configuration
├── services/
│   ├── field_merger.rb      # Trust-based field selection
│   ├── trust_calculator.rb  # Trust score calculation
│   └── conflict_formatter.rb # Conflict reporting
```

### 2.2 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTERNAL SOURCES                                 │
│  (CSV files, JSON APIs, HTML scrapes, government registries)            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      SOURCE-SPECIFIC IMPORTERS                          │
│                                                                         │
│  Processors::Aircraft::CASA::CSV      → Source::Aircraft::CASAAircraftSource
│  Processors::Aircraft::VRS::StandingData → Source::Aircraft::VRSAircraftSource
│  Processors::Operator::OpenTravel     → Source::Operator::OpenTravelOperatorSource
│  Processors::Airport::OurAirports     → Source::Airport::OurAirportsAirportSource
│  ...                                                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SOURCE TABLES (STI)                             │
│                                                                         │
│  aircraft_sources     - CASAAircraftSource, VRSAircraftSource, ...     │
│  operator_sources     - VRSDataOperatorSource, OpenTravelOperatorSource │
│  airport_sources      - OurAirportsAirportSource, OpenFlightsAirportSource
│  country_sources      - OpenTravelCountrySource, OurAirportsCountrySource
│  ...                                                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        COMBINE PROCESSORS                               │
│                                                                         │
│  Uses FieldMerger + TrustCalculator to resolve conflicts               │
│  Groups sources by unique identifier (ICAO, registration, etc.)        │
│  Selects highest-trust value for each field                            │
│  Records provenance for every field                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       CANONICAL TABLES                                  │
│                                                                         │
│  Aircraft      - with field_provenance, last_combined_at               │
│  Operator      - with field_provenance, last_combined_at               │
│  Airport       - with field_provenance, last_combined_at               │
│  Country       - with field_provenance, last_combined_at               │
│  Manufacturer  - with field_provenance, last_combined_at               │
│  AircraftType  - with field_provenance, last_combined_at               │
│  AirportRunway - with field_provenance, last_combined_at               │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Source System

### 3.1 Source Tables

Each entity type has a corresponding source table using Single Table Inheritance (STI):

| Canonical Table  | Source Table           | STI Classes                                           |
|------------------|------------------------|-------------------------------------------------------|
| `aircraft`       | `aircraft_sources`     | CASAAircraftSource, CAANZAircraftSource, VRSAircraftSource, OpenskyAircraftSource |
| `aircraft_types` | `aircraft_type_sources`| CfappsICAOIntAircraftTypeSource, OpenFlightsAircraftTypeSource, VRSAircraftTypeSource |
| `airports`       | `airport_sources`      | OurAirportsAirportSource, OpenFlightsAirportSource    |
| `countries`      | `country_sources`      | OpenTravelCountrySource, OpenFlightsCountrySource, OurAirportsCountrySource |
| `manufacturers`  | `manufacturer_sources` | CfappsIcaoIntManufacturerSource, OpenskyManufacturerSource |
| `operators`      | `operator_sources`     | VRSDataOperatorSource, OpenTravelOperatorSource, OpenFlightsOperatorSource |
| `airport_runways`| `runway_sources`       | OurAirportsRunwaySource                               |

### 3.2 Common Source Fields

Every source table includes:

| Column        | Type     | Purpose                                          |
|---------------|----------|--------------------------------------------------|
| `type`        | string   | STI discriminator (e.g., "CASAAircraftSource")   |
| `data`        | jsonb    | Flexible storage for source-specific fields      |
| `import_date` | datetime | When this record was imported from the source    |
| `created_at`  | datetime | Record creation timestamp                        |
| `updated_at`  | datetime | Last update timestamp                            |

**Why JSONB `data` column?**

Different sources provide different fields. The `data` column stores source-specific attributes without requiring schema migrations. For example, VRS provides `positioning_flight_pattern` while OpenTravel provides `validity_start_date` - both are stored in `data`.

### 3.3 Source Class Hierarchy

```ruby
# Base class for all aircraft sources
class Source::Aircraft::AircraftSource < ApplicationRecord
  self.table_name = 'aircraft_sources'

  validates :icao, :registration, :import_date, presence: true
end

# Australian CASA registry source
class Source::Aircraft::CASAAircraftSource < Source::Aircraft::AircraftSource
  # Inherits from base, adds CASA-specific behaviour
  # Default country: Australia
end

# New Zealand CAANZ registry source
class Source::Aircraft::CAANZAircraftSource < Source::Aircraft::AircraftSource
  # Default country: New Zealand
end
```

### 3.4 Source Registry

The `SourceRegistry` concern (`app/models/concerns/source_registry.rb`) provides metadata about each source for attribution:

```ruby
SourceRegistry.for('VRSDataOperatorSource')
# => {
#   name: "Virtual Radar Server Database",
#   url: "https://github.com/vradarserver/standing-data",
#   license: "BSD-2-Clause",
#   description: "Community-maintained airline operator database"
# }
```

This metadata is used in API responses and UI to attribute data to its original source.

---

## 4. Processor System

### 4.1 Base Processor

All processors inherit from `Processors::Base` which provides:

```ruby
class Processors::Base
  BATCH_SIZE = 1000

  class << self
    # HTTP fetching with mocking support for tests
    def get_source_from_url(url)

    # Creates an import report for tracking
    def new_import_report(errors, record_count)

    # Progress bar for console feedback
    def create_progress_bar(title:, total:)

    # Suppresses SQL logging during bulk operations
    def silence_active_record

    # Wraps bulk operations with optimisations:
    # - Disables PaperTrail versioning
    # - Deactivates MeiliSearch indexing
    # - Silences SQL logging
    def with_bulk_import

    # Batch upsert with configurable batch size
    def batch_upsert(records, model:, unique_by:, batch_size: BATCH_SIZE)
  end
end
```

### 4.2 Two-Tier Processor Pattern

Each entity type has two categories of processors:

#### Tier 1: Source Importers
Import raw data from external sources into source tables.

```ruby
# Example: Import Australian aircraft from CASA CSV export
Processors::Aircraft::CASA::CSV.import_from_file('/path/to/casa_export.csv')

# Example: Import operators from VRS GitHub repository
Processors::Operator::VRSData.import_from_github
```

#### Tier 2: Combine Processors
Merge multiple sources into canonical records using trust-based resolution.

```ruby
# Combines all operator sources into canonical Operator records
Processors::Operator::Operator.combine_sources

# Combines all airport sources into canonical Airport records
Processors::Airport::Airport.combine_sources
```

### 4.3 Combine Processor Workflow

The combine phase follows this pattern:

```ruby
class Processors::Airport::Airport < Processors::Base
  def self.combine_sources
    # 1. Preload reference data for O(1) lookups
    preload_reference_data

    # 2. Group sources by unique identifier
    sources_by_identifier = group_sources_by_identifier

    # 3. Process each group with bulk import optimisations
    with_bulk_import do
      sources_by_identifier.each do |identifier, sources|
        # 4. For each field, use FieldMerger to select the best value
        MERGE_FIELDS.each do |field|
          merger = FieldMerger.new(
            sources: sources,
            field: field,
            entity_type: 'Airport'
          )

          record.public_send("#{field}=", merger.best_value)

          # 5. Record provenance
          record.set_provenance(field,
            source: merger.best_source,
            confidence: merger.best_confidence
          )

          # 6. Track conflicts for logging
          if merger.has_conflict?
            conflicts << merger.conflict_details
          end
        end
      end
    end

    # 7. Log conflicts and reindex for search
    log_conflicts(conflicts)
    Airport.reindex!
  end
end
```

### 4.4 Entity-Specific Processors

| Entity       | Source Importers                                    | Combine Processor                        |
|--------------|-----------------------------------------------------|------------------------------------------|
| **Country**  | OpenTravel, OpenFlights, OurAirports                | `Processors::Country::Country`           |
| **Manufacturer** | CfappsICAOInt, Opensky                          | `Processors::Manufacturer::Manufacturer` |
| **AircraftType** | CfappsICAOInt, OpenFlights, VRS                 | `Processors::AircraftType::AircraftType` |
| **Operator** | OpenTravel, VRSData, OpenFlights                    | `Processors::Operator::Operator`         |
| **Airport**  | OurAirports, OpenFlights                            | `Processors::Airport::Airport`           |
| **Runway**   | OurAirports                                         | `Processors::Runway::Runway`             |
| **Aircraft** | CASA CSV, CASA Registry, CAANZ, VRS StandingData    | `Processors::Aircraft::Aircraft`         |

---

## 5. Trust & Provenance System

### 5.1 Why Trust Scores?

Different sources have different reliability characteristics:

- **ICAO official data** (CfappsICAOInt): Authoritative for type codes and designators
- **Government registries** (CASA, CAANZ): Authoritative for aircraft registration in their jurisdiction
- **Community data** (VRS): Good coverage but variable accuracy
- **Historical data** (OpenFlights): May be outdated

The trust system ensures the best available value is selected when sources disagree.

### 5.2 Trust Score Hierarchy

Trust scores are determined in this order:

1. **Database override** (`source_trust_scores` table) - Admin-tunable
2. **Field-specific override** (`SourceConfig.field_overrides`) - Code-defined
3. **Base trust** (`SourceConfig.base_trust`) - Code-defined default
4. **System default** (50) - Unknown sources

### 5.3 SourceConfig

Centralised trust configuration in `app/models/source_config.rb`:

```ruby
class SourceConfig
  VERY_HIGH_TRUST = 95   # Official government/ICAO sources
  HIGH_TRUST = 85        # Government sources with caveats
  MODERATE_HIGH_TRUST = 80
  MODERATE_TRUST = 70
  LOW_TRUST = 40
  DEFAULT_TRUST = 50

  CONFIGS = {
    'CASAAircraftSource' => {
      base_trust: HIGH_TRUST,  # 85
      field_overrides: {
        # CASA operator/owner data is unreliable (shows registered holder, not operator)
        operator: LOW_TRUST,      # 40
        operator_name: LOW_TRUST, # 40
        owner: LOW_TRUST          # 40
      },
      modifiers: {
        # Boost confidence for Australian-registered aircraft (ICAO prefix 7C)
        icao: {
          filter: ->(record) { record.icao&.match?(/\A7C/i) },
          adjust: ->(trust) { [trust + 10, 100].min }
        }
      }
    },

    'CfappsICAOIntAircraftTypeSource' => {
      base_trust: VERY_HIGH_TRUST,  # 95 - Official ICAO data
      field_overrides: {},
      modifiers: {}
    },

    'OpenTravelOperatorSource' => {
      base_trust: MODERATE_TRUST,  # 70
      field_overrides: {
        name: HIGH_TRUST  # 85 - OpenTravel has particularly reliable names
      },
      modifiers: {}
    }
  }
end
```

### 5.4 TrustCalculator

The `TrustCalculator` service computes the final trust score:

```ruby
calculator = TrustCalculator.new(
  source_record,
  field: :name,
  entity_type: 'Operator'
)

score = calculator.calculate
# => 85 (after applying base trust, field overrides, and modifiers)
```

### 5.5 FieldMerger

The `FieldMerger` service selects the best value from multiple sources:

```ruby
merger = FieldMerger.new(
  sources: [vrs_source, open_travel_source],
  field: :name,
  entity_type: 'Operator'
)

merger.best_value      # => "Qantas Airways"
merger.best_source     # => <OpenTravelOperatorSource id=456>
merger.best_confidence # => 85
merger.has_conflict?   # => true (sources disagree)
merger.conflict_details # => detailed conflict info for logging
```

**Data Quality Filters**:

- Elevation/altitude: Zero values treated as missing (not sea level)
- Coordinates: Differences < 0.001 degrees (~100m) are not considered conflicts

### 5.6 Field Provenance

Every canonical model includes `HasFieldProvenance` which tracks the source of each field:

```ruby
# Structure stored in field_provenance JSONB column
{
  "name": {
    "source_type": "OpenTravelOperatorSource",
    "source_id": 456,
    "confidence": 85,
    "combined_at": "2024-12-24T10:30:00Z"
  },
  "icao_code": {
    "source_type": "VRSDataOperatorSource",
    "source_id": 123,
    "confidence": 80,
    "combined_at": "2024-12-24T10:30:00Z"
  }
}
```

**Setting Provenance**:

```ruby
# From a source record
airport.set_provenance(:name, source: source_record, confidence: 85)

# For derived/calculated values (e.g., timezone from coordinates)
airport.set_derived_provenance(
  :timezone,
  source_name: 'OpenStreetMap/TimezoneBoundaryBuilder',
  confidence: 90
)
```

**Querying Provenance**:

```ruby
airport.provenance_for(:name)
# => { "source_type" => "OurAirportsAirportSource", "source_id" => 789, ... }

airport.provenance_source_for(:name)
# => "OurAirportsAirportSource"

airport.provenance_confidence_for(:name)
# => 85

# Find all airports where name came from OurAirports
Airport.with_field_source(:name, 'OurAirportsAirportSource')

# Find auto-generated stub records that need real data
Manufacturer.needs_enrichment(:name)
```

### 5.7 Auto-Generated Records

When a canonical record is needed but doesn't exist (e.g., an aircraft references a manufacturer not in our data), a stub record is created with special provenance:

```ruby
manufacturer = Manufacturer.create!(
  icao_code: 'UNKN',
  name: 'Unknown Manufacturer'
)
manufacturer.set_derived_provenance(:name, source_name: 'AutoGenerated', confidence: 0)
```

This allows the pipeline to continue while flagging records that need enrichment from real sources.

---

## 6. Import Order & Dependencies

### 6.1 Dependency Graph

```
                    ┌────────────┐
                    │  Country   │
                    └─────┬──────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
    ┌───────────┐   ┌───────────┐   ┌───────────┐
    │Manufacturer│   │  Airport  │   │  Operator │
    └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
          │               │               │
          ▼               ▼               │
    ┌───────────┐   ┌───────────┐         │
    │AircraftType│   │  Runway   │         │
    └─────┬─────┘   └───────────┘         │
          │                               │
          └───────────────┬───────────────┘
                          │
                          ▼
                    ┌───────────┐
                    │  Aircraft │
                    └───────────┘
```

### 6.2 Recommended Import Order

The import order must respect foreign key dependencies. Follow this sequence:

#### Phase 1: Foundation Data (No Dependencies)

```ruby
# 1. Countries - Required by airports, manufacturers, operators
#    Option A: Sync from ISO 3166 (quick, built-in)
Country.sync_from_iso3166!

#    Option B: Import from sources (more complete data)
Processors::Country::OpenTravel.import_from_url(...)
Processors::Country::OurAirports.import_from_url(...)
Processors::Country::Country.combine_sources
```

#### Phase 2: Reference Data (Depends on Country)

```ruby
# 2. Manufacturers - Referenced by aircraft types
Processors::Manufacturer::CfappsIcaoInt.import_from_url(...)
Processors::Manufacturer::Manufacturer.combine_sources

# 3. Aircraft Types - Referenced by aircraft
Processors::AircraftType::CfappsIcaoInt.import_from_url(...)
Processors::AircraftType::OpenFlights.import_from_url(...)  # Adds IATA codes
Processors::AircraftType::AircraftType.combine_sources

# 4. Operators - Referenced by aircraft and routes
Processors::Operator::VRSData.import_from_github
Processors::Operator::OpenTravel.import_from_url(...)
Processors::Operator::Operator.combine_sources

# 5. Airports - Referenced by routes, runways
Processors::Airport::OurAirports.import_from_url(...)
Processors::Airport::OpenFlights.import_from_url(...)
Processors::Airport::Airport.combine_sources
```

#### Phase 3: Dependent Data

```ruby
# 6. Runways - Depends on airports
Processors::Runway::OurAirports.import_from_url(...)
Processors::Runway::Runway.combine_sources

# 7. Aircraft - Depends on aircraft types, operators, countries
Processors::Aircraft::VRS::StandingData.import_from_github  # Global coverage
Processors::Aircraft::CASA::CSV.import_from_file(...)       # Australian aircraft
Processors::Aircraft::CAANZ::Registry.import_all            # NZ aircraft
Processors::Aircraft::Aircraft.combine_sources
```

### 6.3 Full Import Script

```ruby
# Full initial import sequence
Rails.logger.info "Starting full data import..."

# Phase 1: Countries
Rails.logger.info "Phase 1: Importing countries..."
Country.sync_from_iso3166!

# Phase 2: Reference data
Rails.logger.info "Phase 2: Importing manufacturers..."
Processors::Manufacturer::CfappsIcaoInt.import_from_url(
  'https://www.icao.int/publications/DOC8643/Pages/Manufacturers.aspx'
)
Processors::Manufacturer::Manufacturer.combine_sources

Rails.logger.info "Phase 2: Importing aircraft types..."
Processors::AircraftType::CfappsIcaoInt.import_from_url(
  'https://www.icao.int/publications/DOC8643/Pages/Search.aspx'
)
Processors::AircraftType::AircraftType.combine_sources

Rails.logger.info "Phase 2: Importing operators..."
Processors::Operator::VRSData.import_from_github
Processors::Operator::OpenTravel.import_from_url(
  'https://opentravel.org/...'
)
Processors::Operator::Operator.combine_sources

Rails.logger.info "Phase 2: Importing airports..."
Processors::Airport::OurAirports.import_from_url(
  'https://davidmegginson.github.io/ourairports-data/airports.csv'
)
Processors::Airport::Airport.combine_sources

# Phase 3: Dependent data
Rails.logger.info "Phase 3: Importing runways..."
Processors::Runway::OurAirports.import_from_url(
  'https://davidmegginson.github.io/ourairports-data/runways.csv'
)
Processors::Runway::Runway.combine_sources

Rails.logger.info "Phase 3: Importing aircraft..."
Processors::Aircraft::VRS::StandingData.import_from_github
Processors::Aircraft::Aircraft.combine_sources

Rails.logger.info "Import complete!"
```

### 6.4 Incremental Updates

For ongoing updates, import and combine can be run independently:

```ruby
# Daily VRS update
Processors::Aircraft::VRS::StandingData.import_from_github
Processors::Aircraft::Aircraft.combine_sources

# Weekly airport data refresh
Processors::Airport::OurAirports.import_from_url(...)
Processors::Airport::Airport.combine_sources
Processors::Runway::OurAirports.import_from_url(...)
Processors::Runway::Runway.combine_sources
```

---

## 7. Examples

### 7.1 Adding a New Source

To add a new aircraft source (e.g., FAA registry):

```ruby
# 1. Create source model (app/models/source/aircraft/faa_aircraft_source.rb)
module Source
  module Aircraft
    class FAAAircraftSource < AircraftSource
      # FAA-specific defaults or behaviour
      def default_country_code
        'US'
      end
    end
  end
end

# 2. Create processor (app/models/processors/aircraft/faa/registry.rb)
module Processors
  module Aircraft
    module FAA
      class Registry < Processors::Base
        def self.import_from_url(url)
          response = get_source_from_url(url)
          records = parse_faa_format(response.body)

          with_bulk_import do
            batch_upsert(
              records,
              model: Source::Aircraft::FAAAircraftSource,
              unique_by: :registration
            )
          end
        end
      end
    end
  end
end

# 3. Add trust configuration (app/models/source_config.rb)
'FAAAircraftSource' => {
  base_trust: HIGH_TRUST,  # 85 - Official government source
  field_overrides: {},
  modifiers: {
    icao: {
      filter: ->(r) { r.icao&.match?(/\AA[0-9A-F]/i) },  # US ICAO prefix
      adjust: ->(trust) { [trust + 10, 100].min }
    }
  }
}

# 4. Register source metadata (app/models/concerns/source_registry.rb)
'FaaAircraftSource' => {
  name: 'FAA Aircraft Registry',
  url: 'https://registry.faa.gov/',
  license: 'Public Domain',
  description: 'US Federal Aviation Administration aircraft registration database'
}

# 5. Add trust score seeds (db/seeds.rb)
{ entity_type: 'Aircraft', source_type: 'FAAAircraftSource', base_trust: 85 }
```

### 7.2 Investigating Data Provenance

```ruby
# Find where an aircraft's operator came from
aircraft = Aircraft.find_by(registration: 'VH-OQA')
aircraft.provenance_for(:operator_id)
# => { "source_type" => "VRSAircraftSource", "source_id" => 12345, "confidence" => 75, ... }

# Get full source metadata
aircraft.provenance_with_source(:operator_id)
# => {
#   "source_type" => "VRSAircraftSource",
#   "source_id" => 12345,
#   "confidence" => 75,
#   "combined_at" => "2024-12-24T10:30:00Z",
#   "source" => {
#     "name" => "Virtual Radar Server Database",
#     "url" => "https://github.com/vradarserver/standing-data",
#     "license" => "BSD-2-Clause"
#   }
# }

# Find all aircraft with operator data from CASA
Aircraft.with_field_source(:operator_id, 'CASAAircraftSource').count
# => 1234

# Find manufacturers that are auto-generated stubs
Manufacturer.needs_enrichment.pluck(:icao_code, :name)
# => [["UNKN", "Unknown (UNKN)"], ...]
```

### 7.3 Re-running Combine with Updated Trust Scores

If trust scores change, re-combine to apply new weights:

```ruby
# Update trust score in database
SourceTrustScore.find_or_create_by!(
  entity_type: 'Operator',
  source_type: 'VRSDataOperatorSource',
  field_name: 'name'
).update!(base_trust: 90)

# Clear any cached trust scores
SourceTrustScore.clear_cache!

# Re-combine operators
Processors::Operator::Operator.combine_sources

# The operator names will now preferentially use VRS data
```

---

## Appendix: Source Trust Scores

### Default Trust Scores by Source

| Entity       | Source                         | Base Trust | Field Overrides                           |
|--------------|--------------------------------|------------|-------------------------------------------|
| **Aircraft** | CASAAircraftSource             | 85         | operator: 40, owner: 40                   |
|              | CAANZAircraftSource            | 85         | operator: 40, owner: 40                   |
|              | VRSAircraftSource              | 65         | operator_name: 75                         |
|              | OpenskyAircraftSource          | 60         | owner: 75, serial_number: 70              |
| **AircraftType** | CfappsICAOIntAircraftTypeSource | 95      | -                                         |
|              | OpenFlightsAircraftTypeSource  | 65         | -                                         |
|              | VRSAircraftTypeSource          | 70         | -                                         |
| **Airport**  | OurAirportsAirportSource       | 85         | -                                         |
|              | OpenFlightsAirportSource       | 70         | elevation: 40                             |
| **Country**  | OpenTravelCountrySource        | 80         | -                                         |
|              | OpenFlightsCountrySource       | 65         | -                                         |
|              | OurAirportsCountrySource       | 75         | -                                         |
| **Manufacturer** | CfappsIcaoIntManufacturerSource | 95     | -                                         |
|              | OpenskyManufacturerSource      | 70         | -                                         |
| **Operator** | VRSDataOperatorSource          | 80         | -                                         |
|              | OpenTravelOperatorSource       | 70         | name: 85                                  |
|              | OpenFlightsOperatorSource      | 60         | -                                         |
| **Runway**   | OurAirportsRunwaySource        | 85         | -                                         |

### Trust Score Rationale

- **95 (VERY_HIGH)**: Official ICAO data - authoritative by definition
- **85 (HIGH)**: Government registries - official but may have specific weaknesses
- **80 (MODERATE_HIGH)**: Well-curated community data
- **70 (MODERATE)**: Good quality but not authoritative
- **65**: Mixed reliability
- **60**: Historical or less-maintained sources
- **40 (LOW)**: Known to be unreliable for this field
- **50 (DEFAULT)**: Unknown sources - neutral starting point