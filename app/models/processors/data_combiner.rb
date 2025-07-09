# frozen_string_literal: true

require 'jaro_winkler'

module Processors
  # Core class for combining data from multiple sources using configurable strategies
  #
  # This class implements the generic data combination algorithm that can:
  # - Load data from multiple sources with priorities
  # - Apply various matching strategies (exact, fuzzy, composite)
  # - Resolve conflicts using configurable resolution strategies
  # - Transform and validate data through customizable hooks
  # - Generate comprehensive error reports
  #
  # Example usage:
  #   combiner = DataCombiner.new(config)
  #   result = combiner.execute
  #   puts result.summary
  class DataCombiner
    attr_reader :config, :processor_class, :result

    def initialize(config, processor_class = nil)
      @config = config
      @processor_class = processor_class
      @result = CombinerResult.new
      @source_data = {}
      @source_indexes = {}
    end

    # Execute the data combination process
    # @return [CombinerResult] result object with metrics and errors
    def execute
      validate_configuration
      load_and_index_sources
      perform_matching_and_combination
      handle_unmatched_records
      generate_final_report
      @result
    end

    private

    # Validate the configuration before processing
    def validate_configuration
      errors = @config.validate
      unless errors.empty?
        @result.add_configuration_errors(errors)
        raise ArgumentError, "Configuration validation failed: #{errors.join(', ')}"
      end
    end

    # Load data from all sources and build indexes for efficient matching
    def load_and_index_sources
      @config.sources_by_priority.each do |source_config|
        source_name = source_config[:name]
        source_model = source_config[:model]
        
        Rails.logger.info "Loading data from source: #{source_name}"
        
        begin
          # Load all records from the source
          records = source_model.all.to_a
          @source_data[source_name] = records
          @result.add_source_metrics(source_name, records.count, 0)
          
          # Build indexes for efficient matching
          @source_indexes[source_name] = build_source_index(records, source_name)
          
          Rails.logger.info "Loaded #{records.count} records from #{source_name}"
        rescue StandardError => e
          @result.add_source_error(source_name, "Failed to load source: #{e.message}")
          Rails.logger.error "Failed to load source #{source_name}: #{e.message}"
        end
      end
    end

    # Build index for a source to enable efficient matching
    def build_source_index(records, source_name)
      index = {}
      
      records.each do |record|
        # Build indexes for each matching key combination
        @config.matching.keys.each do |key_config|
          key_config[:fields].each do |field|
            field_value = extract_field_value(record, field, source_name)
            next if field_value.nil?
            
            # Normalize value for indexing
            normalized_value = normalize_for_matching(field_value, key_config[:strategy])
            
            index[field] ||= {}
            index[field][normalized_value] ||= []
            index[field][normalized_value] << record
          end
        end
      end
      
      index
    end

    # Perform matching and combination of records
    def perform_matching_and_combination
      primary_source = @config.sources_by_priority.first
      primary_records = @source_data[primary_source[:name]] || []
      
      primary_records.each do |primary_record|
        begin
          # Apply pre-match hook if configured
          processed_record = apply_hook(:pre_match, primary_record)
          
          # Find matches from other sources
          matches = find_matches_for_record(processed_record, primary_source[:name])
          
          # Combine the primary record with matches
          combined_record = combine_records(processed_record, matches, primary_source[:name])
          
          # Apply post-match hook if configured
          final_record = apply_hook(:post_match, combined_record)
          
          # Create or update the target model record
          create_or_update_target_record(final_record)
          
          # Mark matched records as processed
          mark_records_as_processed(matches)
          
        rescue StandardError => e
          @result.add_combination_error(primary_source[:name], primary_record.id, e.message, primary_record)
          Rails.logger.error "Failed to process record #{primary_record.id}: #{e.message}"
        end
      end
    end

    # Find matching records from other sources for a given record
    def find_matches_for_record(record, source_name)
      matches = {}
      
      # Try each matching key in order
      @config.matching.keys.each do |key_config|
        if key_config[:required] && matches.empty?
          # Required key - must find matches
          key_matches = find_matches_by_key(record, source_name, key_config)
          matches.merge!(key_matches) unless key_matches.empty?
        elsif key_config[:fallback] && matches.empty?
          # Fallback key - only try if no previous matches
          key_matches = find_matches_by_key(record, source_name, key_config)
          matches.merge!(key_matches) unless key_matches.empty?
        end
      end
      
      matches
    end

    # Find matches using a specific key configuration
    def find_matches_by_key(record, source_name, key_config)
      matches = {}
      
      # Get values for the key fields from the record
      key_values = key_config[:fields].map do |field|
        extract_field_value(record, field, source_name)
      end
      
      # Skip if any required field is missing
      return matches if key_values.any?(&:nil?)
      
      # Search other sources for matches
      other_sources = @config.sources.reject { |s| s[:name] == source_name }
      
      other_sources.each do |other_source|
        other_source_name = other_source[:name]
        candidates = find_candidates_in_source(key_values, key_config, other_source_name)
        
        candidates.each do |candidate|
          score = calculate_match_score(record, candidate, key_config, source_name, other_source_name)
          
          if score >= (key_config[:threshold] || 0.8)
            matches[other_source_name] ||= []
            matches[other_source_name] << { record: candidate, score: score }
          end
        end
      end
      
      # Sort matches by score (highest first)
      matches.each do |source, source_matches|
        matches[source] = source_matches.sort_by { |m| -m[:score] }
      end
      
      matches
    end

    # Find candidate records in a source that might match
    def find_candidates_in_source(key_values, key_config, source_name)
      candidates = []
      source_index = @source_indexes[source_name]
      
      if key_config[:strategy] == :exact
        # For exact matching, use index lookup
        key_config[:fields].each_with_index do |field, index|
          value = key_values[index]
          normalized_value = normalize_for_matching(value, :exact)
          
          if source_index[field] && source_index[field][normalized_value]
            candidates.concat(source_index[field][normalized_value])
          end
        end
      else
        # For fuzzy matching, we need to check all records
        source_records = @source_data[source_name] || []
        candidates = source_records.select do |candidate|
          # Basic filtering can be done here
          true
        end
      end
      
      candidates.uniq
    end

    # Calculate match score between two records
    def calculate_match_score(record1, record2, key_config, source1_name, source2_name)
      field_scores = []
      
      key_config[:fields].each do |field|
        value1 = extract_field_value(record1, field, source1_name)
        value2 = extract_field_value(record2, field, source2_name)
        
        score = case key_config[:strategy]
                when :exact
                  calculate_exact_match_score(value1, value2)
                when :fuzzy
                  calculate_fuzzy_match_score(value1, value2)
                else
                  0.0
                end
        
        field_scores << score
      end
      
      # Return average score across all fields
      field_scores.empty? ? 0.0 : field_scores.sum / field_scores.length
    end

    # Calculate exact match score
    def calculate_exact_match_score(value1, value2)
      return 0.0 if value1.nil? || value2.nil?
      
      normalized1 = normalize_for_matching(value1, :exact)
      normalized2 = normalize_for_matching(value2, :exact)
      
      normalized1 == normalized2 ? 1.0 : 0.0
    end

    # Calculate fuzzy match score using JaroWinkler
    def calculate_fuzzy_match_score(value1, value2)
      return 0.0 if value1.nil? || value2.nil?
      
      str1 = value1.to_s.strip
      str2 = value2.to_s.strip
      
      return 0.0 if str1.empty? || str2.empty?
      
      JaroWinkler.distance(str1, str2)
    end

    # Normalize values for matching
    def normalize_for_matching(value, strategy)
      return nil if value.nil?
      
      case strategy
      when :exact
        value.to_s.strip.downcase
      when :fuzzy
        value.to_s.strip
      else
        value.to_s.strip
      end
    end

    # Extract field value from a record for a specific source
    def extract_field_value(record, field, source_name)
      field_config = @config.fields[field]
      return nil unless field_config
      
      source_mapping = field_config.sources[source_name]
      return nil unless source_mapping
      
      source_field = source_mapping[:field]
      
      # Try different ways to extract the value
      value = if record.respond_to?(source_field)
                record.send(source_field)
              elsif record.respond_to?(:[])
                record[source_field] || record[source_field.to_sym]
              else
                nil
              end
      
      # Apply source-specific transformation if configured
      if source_mapping[:transform]
        value = source_mapping[:transform].call(value)
      end
      
      value
    end

    # Combine records from multiple sources
    def combine_records(primary_record, matches, primary_source_name)
      combined_attributes = {}
      
      # Process each configured field
      @config.fields.each do |field_name, field_config|
        values = gather_field_values(primary_record, matches, field_name, primary_source_name)
        resolved_value = resolve_field_conflict(field_name, values, field_config)
        
        # Apply field-level transformation if configured
        if field_config.transform
          resolved_value = field_config.transform.call(resolved_value)
        end
        
        combined_attributes[field_name] = resolved_value
      end
      
      combined_attributes
    end

    # Gather values for a field from all sources
    def gather_field_values(primary_record, matches, field_name, primary_source_name)
      values = {}
      
      # Get value from primary source
      primary_value = extract_field_value(primary_record, field_name, primary_source_name)
      values[primary_source_name] = primary_value if primary_value
      
      # Get values from matched sources
      matches.each do |source_name, source_matches|
        next if source_matches.empty?
        
        # Use the best match for this source
        best_match = source_matches.first[:record]
        match_value = extract_field_value(best_match, field_name, source_name)
        values[source_name] = match_value if match_value
      end
      
      values
    end

    # Resolve conflicts for a field using configured strategy
    def resolve_field_conflict(field_name, values, field_config)
      return nil if values.empty?
      return values.values.first if values.length == 1
      
      # Check for custom conflict resolution hook
      if @config.hooks.conflict_resolution
        return apply_hook(:conflict_resolution, field_name, values, field_config)
      end
      
      # Use built-in conflict resolution strategy
      case field_config.conflict_resolution
      when :prefer_source
        resolve_prefer_source(values, field_config)
      when :prefer_non_null
        resolve_prefer_non_null(values)
      when :longest
        resolve_longest(values)
      when :merge
        resolve_merge(values)
      when :most_recent
        resolve_most_recent(values)
      else
        # Default to prefer_source
        resolve_prefer_source(values, field_config)
      end
    end

    # Resolve conflict by preferring specific source
    def resolve_prefer_source(values, field_config)
      # Use field-specific preference if set
      if field_config.preference
        return values[field_config.preference] if values[field_config.preference]
      end
      
      # Use global source priority order
      @config.sources_by_priority.each do |source_config|
        source_name = source_config[:name]
        return values[source_name] if values[source_name]
      end
      
      # Fallback to first available value
      values.values.first
    end

    # Resolve conflict by preferring non-null values
    def resolve_prefer_non_null(values)
      non_null_values = values.reject { |_, v| v.nil? || v.to_s.strip.empty? }
      return nil if non_null_values.empty?
      
      # If multiple non-null values, use source priority
      @config.sources_by_priority.each do |source_config|
        source_name = source_config[:name]
        return non_null_values[source_name] if non_null_values[source_name]
      end
      
      non_null_values.values.first
    end

    # Resolve conflict by choosing longest value
    def resolve_longest(values)
      values.values.max_by { |v| v.to_s.length }
    end

    # Resolve conflict by merging values
    def resolve_merge(values)
      # For arrays, concatenate
      if values.values.first.is_a?(Array)
        values.values.flatten.uniq
      # For hashes, merge
      elsif values.values.first.is_a?(Hash)
        values.values.reduce({}) { |acc, hash| acc.merge(hash) }
      # For strings, join with separator
      elsif values.values.first.is_a?(String)
        values.values.join(' | ')
      else
        # Default to first value
        values.values.first
      end
    end

    # Resolve conflict by choosing most recent value
    def resolve_most_recent(values)
      # This would need additional logic to determine recency
      # For now, fallback to source priority
      resolve_prefer_source(values, OpenStruct.new(preference: nil))
    end

    # Apply a hook if configured
    def apply_hook(hook_name, *args)
      hook_method = @config.hooks.send(hook_name)
      return args.first if hook_method.nil? || @processor_class.nil?
      
      @processor_class.send(hook_method, *args)
    end

    # Create or update target model record
    def create_or_update_target_record(combined_attributes)
      target_model = @config.target_model
      
      # Apply validation hook if configured
      if @config.hooks.validation
        validation_result = apply_hook(:validation, combined_attributes)
        unless validation_result
          @result.add_validation_error(combined_attributes)
          return
        end
      end
      
      # Find existing record or create new one
      record = find_or_initialize_target_record(combined_attributes)
      
      # Update attributes
      record.assign_attributes(combined_attributes)
      
      # Validate and save
      if record.valid?
        record.save!
        @result.increment_records_created
      else
        @result.add_validation_error(combined_attributes, record.errors.full_messages)
      end
    end

    # Find or initialize target record
    def find_or_initialize_target_record(attributes)
      target_model = @config.target_model
      
      # Try to find existing record using unique identifiers
      # This is a simplified implementation - in practice, you'd configure
      # which fields to use for finding existing records
      find_attrs = attributes.slice(:icao_code, :iata_code, :name).compact
      
      if find_attrs.any?
        target_model.find_or_initialize_by(find_attrs)
      else
        target_model.new
      end
    end

    # Mark records as processed to avoid processing them again
    def mark_records_as_processed(matches)
      # This could be implemented by maintaining a set of processed record IDs
      # For now, we'll rely on the processing order
    end

    # Handle unmatched records from lower priority sources
    def handle_unmatched_records
      # This would process records from lower priority sources that weren't matched
      # Implementation depends on specific requirements
    end

    # Generate final processing report
    def generate_final_report
      @result.finalize
      Rails.logger.info "Data combination completed: #{@result.summary}"
    end
  end

  # Result object for tracking combination metrics and errors
  class CombinerResult
    attr_reader :source_metrics, :errors, :records_created, :records_updated, :start_time, :end_time

    def initialize
      @source_metrics = {}
      @errors = {
        configuration: [],
        source_loading: [],
        matching: [],
        combination: [],
        validation: []
      }
      @records_created = 0
      @records_updated = 0
      @start_time = Time.current
      @end_time = nil
    end

    def add_source_metrics(source_name, records_loaded, records_processed)
      @source_metrics[source_name] = {
        records_loaded: records_loaded,
        records_processed: records_processed
      }
    end

    def add_configuration_errors(errors)
      @errors[:configuration].concat(errors)
    end

    def add_source_error(source_name, error)
      @errors[:source_loading] << { source: source_name, error: error }
    end

    def add_matching_error(strategy, field, error)
      @errors[:matching] << { strategy: strategy, field: field, error: error }
    end

    def add_combination_error(source, record_id, error, raw_data = nil)
      @errors[:combination] << { 
        source: source, 
        record_id: record_id, 
        error: error, 
        raw_data: raw_data 
      }
    end

    def add_validation_error(combined_data, validation_errors = [])
      @errors[:validation] << { 
        combined_data: combined_data, 
        validation_errors: validation_errors 
      }
    end

    def increment_records_created
      @records_created += 1
    end

    def increment_records_updated
      @records_updated += 1
    end

    def finalize
      @end_time = Time.current
    end

    def duration
      return nil unless @end_time
      @end_time - @start_time
    end

    def success?
      @errors.values.flatten.empty?
    end

    def total_errors
      @errors.values.flatten.length
    end

    def summary
      {
        records_created: @records_created,
        records_updated: @records_updated,
        total_errors: total_errors,
        duration: duration,
        success: success?
      }
    end
  end
end