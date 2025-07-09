# Generic Data Combiner Implementation Guide

## Overview

This document provides comprehensive documentation for the generic data combiner implementation in the Aerodex application. The combiner provides a flexible, configurable system for combining data from multiple sources with sophisticated matching and conflict resolution strategies.

## Implementation Files

### Core Components

1. **`app/models/processors/combiner_config.rb`** - Configuration classes and DSL
2. **`app/models/processors/data_combiner.rb`** - Core combination algorithm
3. **`app/models/processors/base.rb`** - Extended base class with combiner methods
4. **`app/models/processors/test_combiner_processor.rb`** - Test processor for validation

### File Structure

```
app/models/processors/
├── base.rb                      # Extended with combiner methods
├── combiner_config.rb           # Configuration DSL classes
├── data_combiner.rb             # Core combination algorithm
└── test_combiner_processor.rb   # Safe testing processor
```

## Configuration System

### CombinerConfig Class

The main configuration class that provides the DSL for setting up data combination:

```ruby
config = CombinerConfig.new
config.sources do
  source Source::ModelA, priority: 1, name: :source_a
  source Source::ModelB, priority: 2, name: :source_b
end

config.target_model ::TargetModel

config.fields do
  field :name do
    from :source_a, field: 'name'
    from :source_b, field: 'company_name'
    prefer :source_a
    resolve_conflicts :prefer_source
  end
end
```

### Configuration Classes

- **`CombinerConfig`** - Main configuration container
- **`SourcesConfig`** - Manages source definitions
- **`FieldsConfig`** - Manages field mapping definitions
- **`FieldConfig`** - Individual field configuration
- **`MatchingConfig`** - Matching strategy configuration
- **`HooksConfig`** - Custom hook configuration

### Validation

All configuration classes include validation to ensure:
- Required fields are present
- Source priorities are valid
- Field mappings are complete
- Matching strategies are properly configured

## Data Combination Algorithm

### Core Algorithm Flow

1. **Source Preparation**
   - Load data from all configured sources
   - Build indexes for efficient matching
   - Apply source-specific transformations

2. **Matching**
   - Apply matching strategies in priority order
   - Build candidate sets from other sources
   - Score matches based on configured strategies

3. **Combination**
   - Apply field-level preference rules
   - Resolve conflicts using configured strategies
   - Apply custom decision hooks
   - Validate combined records

4. **Output**
   - Create/update target model records
   - Handle unmatched records
   - Generate comprehensive error reports

### DataCombiner Class

The core class that implements the combination algorithm:

```ruby
combiner = DataCombiner.new(config, processor_class)
result = combiner.execute
```

Key features:
- **Configurable matching strategies** (exact, fuzzy, composite)
- **Flexible conflict resolution** (prefer_source, prefer_non_null, longest, merge)
- **Comprehensive error handling** with detailed reporting
- **Performance optimization** through indexing and caching
- **Hook system** for custom processing logic

## Matching Strategies

### Exact Matching

Direct field comparison with normalization:

```ruby
config.matching do
  strategy :exact
  key [:code, :name], exact: true, required: true
end
```

### Fuzzy Matching

Uses JaroWinkler distance for approximate matching:

```ruby
config.matching do
  strategy :fuzzy
  key [:name], fuzzy: true, threshold: 0.8, fallback: true
end
```

### Composite Matching

Combines multiple matching strategies with fallback:

```ruby
config.matching do
  strategy :composite
  key [:icao_code, :name], exact: true, required: true
  key [:iata_code, :name], exact: true, fallback: true
  key [:name], fuzzy: true, threshold: 0.75, fallback: true
end
```

## Conflict Resolution Strategies

### Built-in Strategies

1. **`prefer_source`** - Use source priority order
2. **`prefer_non_null`** - Choose non-null/non-empty values
3. **`longest`** - Choose longest string value
4. **`merge`** - Combine values (arrays, hashes, strings)
5. **`most_recent`** - Choose most recent value (if timestamp available)

### Custom Resolution

```ruby
config.hooks do
  conflict_resolution :custom_resolver
end

def self.custom_resolver(field, values, sources, context)
  case field
  when :name
    values.find { |v| v&.length > 5 } || values.first
  else
    values.first
  end
end
```

## Hook System

### Available Hooks

- **`pre_match`** - Process records before matching
- **`post_match`** - Process records after matching
- **`conflict_resolution`** - Custom conflict resolution
- **`validation`** - Custom validation logic
- **`pre_transform`** - Pre-transformation processing
- **`post_transform`** - Post-transformation processing

### Hook Implementation

```ruby
config.hooks do
  pre_match :preprocess_record
  post_match :validate_business_rules
end

def self.preprocess_record(record)
  record[:name] = normalize_name(record[:name]) if record[:name]
  record
end

def self.validate_business_rules(combined_record)
  # Custom validation logic
  true
end
```

## Error Handling and Reporting

### Error Types

The system tracks and reports five types of errors:

1. **Configuration Errors** - Invalid configuration
2. **Source Loading Errors** - Failed to load source data
3. **Matching Errors** - Failed to find matches
4. **Combination Errors** - Failed to combine records
5. **Validation Errors** - Failed validation rules

### CombinerResult Class

Comprehensive result tracking:

```ruby
result = combiner.execute

puts result.summary
# => {
#   records_created: 150,
#   records_updated: 25,
#   total_errors: 3,
#   duration: 2.5,
#   success: true
# }
```

### Error Details

```ruby
result.errors[:validation].each do |error|
  puts "Validation Error: #{error[:validation_errors].join(', ')}"
  puts "Data: #{error[:combined_data]}"
end
```

## Integration with Processors::Base

### New Methods Added

- **`configure_combiner`** - Set up combiner configuration
- **`combine_sources_generic`** - Execute generic combiner
- **`combine_sources_with_transaction`** - Execute with transaction wrapper
- **`combiner_config`** - Get current configuration
- **`combiner_configured?`** - Check if combiner is configured

### Backward Compatibility

The system maintains full backward compatibility:

- Existing processors continue to work unchanged
- New `combine_sources` method delegates to existing implementations
- Only uses generic combiner if configured

## Usage Examples

### Simple Single-Source Combination

```ruby
class AircraftTypeProcessor < Processors::Base
  configure_combiner do |config|
    config.sources do
      source Source::AircraftType::CfappsICAOIntAircraftTypeSource, priority: 1, name: :cfapps
    end
    
    config.target_model ::AircraftType
    
    config.fields do
      field :type_code, from: { cfapps: 'type_code' }
      field :name, from: { cfapps: 'name' }
      field :manufacturer do
        from :cfapps, field: 'manufacturer'
        transform ->(value) { ::Manufacturer.find_by(icao_code: value) }
      end
    end
    
    config.matching do
      strategy :exact
      key [:type_code, :name], exact: true, required: true
    end
  end
end

# Execute
result = AircraftTypeProcessor.combine_sources_generic
```

### Complex Multi-Source Combination

```ruby
class OperatorProcessor < Processors::Base
  configure_combiner do |config|
    config.sources do
      source Source::Operator::VRSDataOperatorSource, priority: 1, name: :vrs
      source Source::Operator::OpenTravelOperatorSource, priority: 2, name: :open_travel
    end
    
    config.target_model ::Operator
    
    config.fields do
      field :name do
        from :vrs, field: 'name', transform: ->(v) { normalize_name(v) }
        from :open_travel, field: 'name', transform: ->(v) { v&.strip }
        prefer :vrs
      end
      
      field :icao_code do
        from :vrs, field: 'icao_code'
        from :open_travel, field: 'icao_code'
        resolve_conflicts :prefer_non_null
      end
    end
    
    config.matching do
      strategy :composite
      key [:icao_code, :name], exact: true, required: true
      key [:iata_code, :name], exact: true, fallback: true
      key [:name], fuzzy: true, threshold: 0.75, fallback: true
    end
    
    config.hooks do
      pre_match :preprocess_names
      post_match :validate_business_rules
    end
  end
  
  private
  
  def self.preprocess_names(record)
    record[:name] = normalize_name(record[:name]) if record[:name]
    record
  end
  
  def self.validate_business_rules(combined_record)
    # Custom validation logic
    true
  end
end

# Execute
result = OperatorProcessor.combine_sources_generic
```

## Testing and Validation

### Test Processor

The `TestCombinerProcessor` provides safe testing capabilities:

```ruby
# Run all tests
results = Processors::TestCombinerProcessor.run_all_tests

# Run specific tests
Processors::TestCombinerProcessor.test_simple_combination
Processors::TestCombinerProcessor.test_complex_combination
```

### Test Coverage

The test processor validates:
- Configuration validation
- Error handling
- Simple single-source combination
- Complex multi-source combination
- Hook system functionality
- Matching strategies
- Conflict resolution

### Safety Features

- **No production data modification** - Uses separate test configurations
- **Comprehensive error handling** - Catches and reports all errors
- **Detailed logging** - Provides clear success/failure messages
- **Isolated testing** - Doesn't affect existing processors

## Performance Considerations

### Optimization Strategies

1. **Indexing** - Pre-builds indexes for efficient matching
2. **Batching** - Processes records in configurable batches
3. **Caching** - Caches expensive transformations
4. **Streaming** - Memory-efficient processing for large datasets

### Memory Management

- **Lazy loading** - Loads data only when needed
- **Garbage collection** - Cleans up intermediate data structures
- **Configurable batch sizes** - Prevents memory exhaustion

### Monitoring

- **Progress tracking** - Reports processing progress
- **Performance metrics** - Tracks processing time and throughput
- **Error reporting** - Comprehensive error collection and reporting

## Security Considerations

### Input Validation

- **Configuration validation** - Ensures all required fields are present
- **Source validation** - Validates source model classes
- **Field validation** - Validates field mappings and transformations

### Error Handling

- **Sanitized error messages** - Prevents sensitive data exposure
- **Controlled execution** - Transactions and rollback capabilities
- **Audit logging** - Tracks all processing activities

## Migration Path

### Phase 1: Implementation Complete ✓
- Generic combiner classes implemented
- Configuration DSL created
- Core algorithm developed
- Test processor created

### Phase 2: Testing and Validation
- Run comprehensive tests
- Validate against existing processors
- Performance benchmarking
- Security review

### Phase 3: Optional Migration
- Create combiner configurations for existing processors
- Side-by-side testing
- Gradual migration (if desired)

### Phase 4: Documentation and Training
- User guides and tutorials
- API documentation
- Best practices guide
- Training materials

## Troubleshooting

### Common Issues

1. **Configuration Errors**
   - Check all required fields are configured
   - Verify source models exist and are accessible
   - Validate field mappings

2. **Matching Failures**
   - Check matching key configurations
   - Verify threshold values for fuzzy matching
   - Test with sample data

3. **Performance Issues**
   - Monitor memory usage
   - Check index effectiveness
   - Consider batch size adjustments

### Debug Mode

Enable detailed logging for troubleshooting:

```ruby
Rails.logger.level = Logger::DEBUG
result = processor.combine_sources_generic
```

### Error Analysis

Use the comprehensive error reporting:

```ruby
result.errors.each do |error_type, errors|
  puts "#{error_type}: #{errors.count} errors"
  errors.each { |error| puts "  - #{error}" }
end
```

## Future Enhancements

### Planned Features

1. **Machine Learning Integration** - Adaptive matching thresholds
2. **Real-time Processing** - Stream processing capabilities
3. **Visual Configuration** - Web UI for configuration
4. **Advanced Caching** - Redis-based distributed caching
5. **Parallel Processing** - Multi-threaded processing support

### Extension Points

- **Custom matching algorithms** - Pluggable matching strategies
- **Additional conflict resolution** - New resolution strategies
- **External service integration** - API-based data sources
- **Enhanced validation** - Advanced validation rules

## Conclusion

The generic data combiner provides a powerful, flexible foundation for combining data from multiple sources while maintaining backward compatibility and safety. The implementation follows the specification requirements with comprehensive error handling, extensive documentation, and safe testing capabilities.

The system is ready for testing and validation, with clear migration paths for existing processors when desired.