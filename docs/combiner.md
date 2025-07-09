# Generic Data Combiner Algorithm Design Specification

## Overview

This document outlines the design for a generic data combiner algorithm that will be added to the `Processors::Base` class. The algorithm will enable processors to combine data from multiple sources with configurable field mapping, source preferences, and custom decision logic.

## Current State Analysis

### Existing Patterns

The current codebase demonstrates several approaches to data combination:

1. **Simple Find-or-Initialize** (Countries, Manufacturers, AircraftTypes):
   - Single source to main model mapping
   - Basic field transformation via `@transform_data`
   - Limited conflict resolution

2. **Complex Manual Combination** (Operators):
   - Full outer join between VRS and OpenTravel sources
   - Fuzzy matching with JaroWinkler distance
   - Manual preference logic (`preferred_attr` method)
   - Transaction-wrapped processing

3. **Transform Field Pattern**:
   - `@transform_data` hash for field mapping and transformation
   - Function-based value transformation
   - Used consistently across all processors

## Algorithm Design

### Core Components

#### 1. Source Configuration System

```ruby
@combiner_config = {
  sources: [
    {
      model: Source::Operator::VRSDataOperatorSource,
      priority: 1,  # Higher number = higher priority
      name: :vrs
    },
    {
      model: Source::Operator::OpenTravelOperatorSource,
      priority: 2,
      name: :open_travel
    }
  ],
  # ... other config
}
```

#### 2. Field Mapping Configuration

Extends the existing `@transform_data` pattern:

```ruby
@combiner_config = {
  # ... sources config
  field_mapping: {
    name: {
      sources: {
        vrs: { field: 'name', transform: ->(value) { normalise_name(value) } },
        open_travel: { field: 'name', transform: ->(value) { value&.strip } }
      },
      preference: :vrs,  # Override global source priority for this field
      conflict_resolution: :prefer_source  # or :merge, :custom
    },
    icao_code: {
      sources: {
        vrs: { field: 'icao_code' },
        open_travel: { field: 'icao_code' }
      },
      conflict_resolution: :prefer_non_null
    }
  }
}
```

#### 3. Matching Strategy Configuration

```ruby
@combiner_config = {
  # ... other config
  matching: {
    strategy: :composite,  # :exact, :fuzzy, :composite, :custom
    keys: [
      {
        fields: [:icao_code, :name],
        strategy: :exact,
        required: true
      },
      {
        fields: [:iata_code, :name],
        strategy: :exact,
        required: false,
        fallback: true
      },
      {
        fields: [:name],
        strategy: :fuzzy,
        threshold: 0.75,
        fallback: true
      }
    ]
  }
}
```

#### 4. Custom Decision Hooks

```ruby
@combiner_config = {
  # ... other config
  hooks: {
    pre_match: :custom_pre_match_logic,
    post_match: :custom_post_match_logic,
    conflict_resolution: :custom_conflict_resolver,
    validation: :custom_validation
  }
}
```

### Algorithm Flow

#### Phase 1: Source Preparation
1. Load all sources based on configuration
2. Apply source-specific transformations
3. Index sources for efficient matching

#### Phase 2: Matching
1. For each record in the highest priority source:
   - Apply matching strategies in order
   - Build candidate sets from other sources
   - Score matches based on strategy

#### Phase 3: Combination
1. For each matched set:
   - Apply field-level preference rules
   - Resolve conflicts using configured strategies
   - Apply custom decision hooks
   - Validate combined record

#### Phase 4: Output
1. Create/update target model records
2. Handle unmatched records from lower priority sources
3. Collect and report errors
4. Generate import report

## API Design

### Core Method Signature

```ruby
def self.combine_sources(config = nil)
  config ||= @combiner_config
  
  combiner = DataCombiner.new(config)
  combiner.execute
end
```

### Configuration DSL

```ruby
class SampleProcessor < Processors::Base
  configure_combiner do |config|
    config.sources do
      source Source::SampleSource1, priority: 1, name: :source1
      source Source::SampleSource2, priority: 2, name: :source2
    end
    
    config.fields do
      field :name do
        from :source1, field: 'name', transform: ->(v) { v&.strip }
        from :source2, field: 'company_name'
        prefer :source1
        resolve_conflicts :prefer_source
      end
      
      field :code do
        from :source1, field: 'code'
        from :source2, field: 'identifier'
        resolve_conflicts :prefer_non_null
      end
    end
    
    config.matching do
      strategy :composite
      key [:code, :name], exact: true, required: true
      key [:name], fuzzy: true, threshold: 0.8, fallback: true
    end
    
    config.hooks do
      pre_match :custom_preprocessing
      post_match :custom_postprocessing
      conflict_resolution :custom_resolver
    end
  end
end
```

## Conflict Resolution Strategies

### Built-in Strategies

1. **prefer_source**: Use global or field-specific source priority
2. **prefer_non_null**: Choose non-null/non-empty value
3. **merge**: Combine values (arrays, hashes)
4. **longest**: Choose longest string value
5. **most_recent**: Choose value from most recent import
6. **custom**: Delegate to custom method

### Custom Strategy Implementation

```ruby
def custom_conflict_resolver(field, values, sources, context)
  case field
  when :name
    # Custom name preference logic
    values.find { |v| v&.length > 5 } || values.first
  when :date_field
    # Most recent date
    values.compact.max
  else
    # Default to source preference
    values.first
  end
end
```

## Matching Algorithms

### Exact Matching
Direct field comparison with optional case sensitivity and normalization.

### Fuzzy Matching
- JaroWinkler distance (existing implementation)
- Levenshtein distance
- Configurable thresholds per field
- Support for multiple field combinations

### Composite Matching
- Multiple key combinations with fallback
- Scoring system for match confidence
- Configurable thresholds for acceptance

### Custom Matching
- Delegate to processor-specific methods
- Access to full record context
- Support for complex business logic

## Error Handling and Reporting

### Error Collection
```ruby
{
  record_errors: [
    {
      source: :vrs,
      record_id: 123,
      errors: ["Name cannot be blank"],
      raw_data: { ... }
    }
  ],
  matching_errors: [
    {
      strategy: :fuzzy,
      field: :name,
      candidates: [...],
      error: "No matches above threshold"
    }
  ],
  combination_errors: [
    {
      target_model: "Operator",
      validation_errors: ["ICAO code already exists"],
      combined_data: { ... }
    }
  ]
}
```

### Success Metrics
- Records processed per source
- Successful matches
- Conflicts resolved
- Records created/updated
- Processing time

## Performance Considerations

### Optimization Strategies
1. **Indexing**: Pre-build indexes for common match keys
2. **Batching**: Process records in configurable batch sizes
3. **Caching**: Cache expensive transformations and matches
4. **Parallel Processing**: Support for concurrent source processing
5. **Memory Management**: Stream processing for large datasets

### Scalability Features
- Configurable batch sizes
- Progress reporting for long-running operations
- Resumable processing with checkpoints
- Memory-efficient streaming for large sources

## Implementation Safety

### Critical Safety Guidelines

**⚠️ DO NOT DISRUPT EXISTING PROCESSORS**

During the development and testing of this new generic combiner algorithm, it is essential that current processors remain completely unaffected:

1. **Parallel Development**: Implement the new combiner system alongside existing processors without modifying them
2. **No Breaking Changes**: Existing `combine_sources` methods in processors must continue to work exactly as they do now
3. **Safe Testing**: Create separate test processors to validate the new system rather than modifying production processors
4. **Independent Validation**: Test the new combiner with copies of existing data sources, not the live processors

### Recommended Development Approach

1. **Phase 1**: Implement the generic `DataCombiner` class and supporting infrastructure in `Processors::Base`
2. **Phase 2**: Create experimental test processors that use the new system (e.g., `TestOperatorCombiner`)
3. **Phase 3**: Validate results against existing processors to ensure equivalent functionality
4. **Phase 4**: Only after thorough testing and validation, consider gradual migration of existing processors

### Testing Strategy for Safety

- Create duplicate processors with `_new` suffix for testing (e.g., `OperatorNew`)
- Use separate test databases or test data to avoid affecting production processing
- Implement comprehensive regression tests comparing old vs new results
- Never modify existing processor methods during development phase

## Migration Strategy

### Backward Compatibility
- Existing processors continue to work unchanged indefinitely
- Opt-in migration to generic combiner only after thorough validation
- Gradual migration path with coexistence supported
- No forced migration until the new system is proven stable

### Migration Steps
1. **Phase 1**: Implement generic combiner in Base class (non-disruptive)
2. **Phase 2**: Create test configurations for existing processors
3. **Phase 3**: Extensive testing and validation phase
4. **Phase 4**: Optional migration of simple processors (Countries, Manufacturers)
5. **Phase 5**: Optional migration of complex processors (Operators)
6. **Phase 6**: Legacy methods can be removed only after all processors are migrated and validated

## Example Implementations

### Simple Aircraft Type Combination

```ruby
class AircraftType < Processors::Base
  configure_combiner do |config|
    config.sources do
      source Source::AircraftType::CfappsICAOIntAircraftTypeSource, priority: 1
    end
    
    config.target_model ::AircraftType
    
    config.fields do
      field :type_code, from: { cfapps: 'type_code' }
      field :name, from: { cfapps: 'name' }
      field :manufacturer do
        from :cfapps, field: 'manufacturer'
        transform ->(value) { ::Manufacturer.find_by(icao_code: value) }
      end
      field :wtc, from: { cfapps: 'wtc' }
      field :engines, from: { cfapps: 'engines' }
      field :engine_type, from: { cfapps: 'engine_type' }
    end
    
    config.matching do
      strategy :exact
      key [:type_code, :name, :manufacturer], required: true
    end
  end
end
```

### Complex Operator Combination

```ruby
class Operator < Processors::Base
  configure_combiner do |config|
    config.sources do
      source Source::Operator::VRSDataOperatorSource, priority: 1, name: :vrs
      source Source::Operator::OpenTravelOperatorSource, priority: 2, name: :open_travel
    end
    
    config.target_model ::Operator
    
    config.fields do
      field :name do
        from :vrs, field: 'name', transform: ->(v) { normalise_name(v) }
        from :open_travel, field: 'name', transform: ->(v) { v&.strip }
        prefer :vrs
      end
      
      field :icao_code do
        from :vrs, field: 'icao_code'
        from :open_travel, field: 'icao_code'
        resolve_conflicts :prefer_non_null
      end
      
      field :iata_code do
        from :vrs, field: 'iata_code'
        from :open_travel, field: 'iata_code'
        resolve_conflicts :prefer_non_null
      end
    end
    
    config.matching do
      strategy :composite
      key [:icao_code, :name], exact: true, required: true
      key [:iata_code, :name], exact: true, fallback: true
      key [:icao_code], fuzzy: true, threshold: 0.5, fallback: true
      key [:iata_code], fuzzy: true, threshold: 0.75, fallback: true
    end
    
    config.hooks do
      pre_match :preprocess_names
      post_match :validate_business_rules
    end
  end
  
  private
  
  def self.preprocess_names(record)
    record[:name] = normalise_name(record[:name]) if record[:name]
    record
  end
  
  def self.validate_business_rules(combined_record)
    # Custom validation logic
    true
  end
end
```

## Testing Strategy

### Unit Tests
- Test individual components (matching, conflict resolution)
- Mock sources for predictable test data
- Test configuration validation

### Integration Tests
- Test with real source data
- Verify end-to-end processing
- Performance benchmarks

### Migration Tests
- Ensure backward compatibility
- Verify equivalent results between old and new implementations
- Test error handling and reporting

## Future Enhancements

### Planned Features
1. **Machine Learning Integration**: Adaptive matching thresholds
2. **Real-time Processing**: Stream processing for continuous updates
3. **Data Quality Metrics**: Automated quality assessment
4. **Visual Configuration**: Web UI for combiner configuration
5. **Advanced Caching**: Redis-based caching for distributed processing

### Extension Points
- Custom matching algorithms
- Additional conflict resolution strategies
- Source-specific preprocessing hooks
- Custom validation rules
- External service integration

## Implementation Notes

### Dependencies
- Existing JaroWinkler implementation
- ActiveRecord for database operations
- Existing error reporting infrastructure

### Configuration Storage
- In-memory configuration objects
- Optional YAML/JSON configuration files
- Database-stored configuration for dynamic updates

### Monitoring and Observability
- Detailed logging for debugging
- Metrics collection for performance monitoring
- Integration with existing error reporting
- Progress tracking for long-running operations

## Documentation Requirements

### Comprehensive Documentation Standards

**All implemented features must include thorough documentation.** This is not optional - comprehensive documentation is required for:

### 1. API Documentation
- **Method signatures** with detailed parameter descriptions
- **Return value specifications** with examples
- **Configuration options** with all possible values documented
- **Error conditions** and exception handling
- **Usage examples** for each major feature

### 2. Configuration Documentation
- **Complete configuration reference** for all options
- **Default values** for all configurable parameters
- **Validation rules** and constraints
- **Best practices** for different use cases
- **Migration guides** from existing processors

### 3. Code Documentation
- **Inline comments** explaining complex logic
- **Class and module documentation** with purpose and usage
- **Method documentation** following Ruby documentation standards
- **Configuration DSL documentation** with examples
- **Hook system documentation** with extension points

### 4. User Guides
- **Getting started guide** for new users
- **Step-by-step tutorials** for common scenarios
- **Advanced usage patterns** for complex configurations
- **Troubleshooting guide** with common issues and solutions
- **Performance optimization guide** with best practices

### 5. Testing Documentation
- **Test strategy documentation** for each component
- **Test data setup** and requirements
- **Regression testing procedures** comparing old vs new
- **Performance testing guidelines** and benchmarks
- **Integration testing scenarios** with real data

### 6. Examples and Samples
- **Working examples** for each processor type
- **Sample configurations** for common use cases
- **Code snippets** demonstrating key features
- **Before/after comparisons** showing migration paths
- **Real-world scenarios** with aviation data

### 7. Implementation Notes
- **Architecture decisions** and rationale
- **Design patterns** used and why
- **Performance considerations** and optimizations
- **Security considerations** and best practices
- **Extension points** for future enhancements

### Documentation Standards
- All documentation must be **kept up-to-date** with code changes
- Use **clear, concise language** suitable for developers
- Include **practical examples** for all features
- Provide **troubleshooting sections** for common issues
- Maintain **version compatibility** notes for breaking changes

### Documentation Deliverables
1. **API Reference Documentation** (generated and manual)
2. **Configuration Guide** with complete option reference
3. **User Guide** with tutorials and examples
4. **Migration Guide** from existing processors
5. **Testing Guide** for validation and regression testing
6. **Performance Guide** for optimization and scaling

**Note**: Documentation should be treated as a first-class deliverable, not an afterthought. Incomplete documentation will be considered incomplete implementation.

This design provides a flexible, extensible foundation for combining data from multiple sources while maintaining backward compatibility and supporting the complex requirements of aviation data processing.