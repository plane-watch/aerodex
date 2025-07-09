# frozen_string_literal: true

module Processors
  # Configuration classes for the generic data combiner system
  # 
  # This module provides a DSL for configuring data combination from multiple sources
  # with support for field mapping, conflict resolution, and matching strategies.
  #
  # Example usage:
  #   config = CombinerConfig.new
  #   config.sources do
  #     source Source::ModelA, priority: 1, name: :source_a
  #     source Source::ModelB, priority: 2, name: :source_b
  #   end
  #   config.fields do
  #     field :name do
  #       from :source_a, field: 'name'
  #       from :source_b, field: 'company_name'
  #       prefer :source_a
  #     end
  #   end
  class CombinerConfig
    attr_reader :sources, :fields, :matching, :hooks, :target_model, :options

    def initialize
      @sources = []
      @fields = {}
      @matching = MatchingConfig.new
      @hooks = HooksConfig.new
      @target_model = nil
      @options = {}
    end

    # Configure sources with the DSL
    # @yield [SourcesConfig] block for configuring sources
    def sources(&block)
      config = SourcesConfig.new(@sources)
      config.instance_eval(&block) if block_given?
      config
    end

    # Configure field mappings with the DSL
    # @yield [FieldsConfig] block for configuring fields
    def fields(&block)
      config = FieldsConfig.new(@fields)
      config.instance_eval(&block) if block_given?
      config
    end

    # Configure matching strategies with the DSL
    # @yield [MatchingConfig] block for configuring matching
    def matching(&block)
      @matching.instance_eval(&block) if block_given?
      @matching
    end

    # Configure hooks with the DSL
    # @yield [HooksConfig] block for configuring hooks
    def hooks(&block)
      @hooks.instance_eval(&block) if block_given?
      @hooks
    end

    # Set the target model class
    # @param model [Class] the target model class to create records for
    def target_model(model)
      @target_model = model
    end

    # Set configuration options
    # @param opts [Hash] configuration options
    def options(opts)
      @options.merge!(opts)
    end

    # Validate the configuration
    # @return [Array<String>] array of validation errors
    def validate
      errors = []
      errors << "No sources configured" if @sources.empty?
      errors << "No target model specified" if @target_model.nil?
      errors << "No fields configured" if @fields.empty?
      
      @sources.each do |source|
        errors << "Source #{source[:name]} missing model" unless source[:model]
        errors << "Source #{source[:name]} missing name" unless source[:name]
        errors << "Source #{source[:name]} missing priority" unless source[:priority]
      end

      @fields.each do |field_name, field_config|
        errors << "Field #{field_name} has no source mappings" if field_config.sources.empty?
      end

      errors.concat(@matching.validate)
      errors
    end

    # Get source configuration by name
    # @param name [Symbol] source name
    # @return [Hash, nil] source configuration or nil if not found
    def source_by_name(name)
      @sources.find { |s| s[:name] == name }
    end

    # Get sources ordered by priority (highest first)
    # @return [Array<Hash>] sources ordered by priority
    def sources_by_priority
      @sources.sort_by { |s| -s[:priority] }
    end
  end

  # Configuration for sources
  class SourcesConfig
    def initialize(sources_array)
      @sources = sources_array
    end

    # Add a source configuration
    # @param model [Class] the source model class
    # @param priority [Integer] priority level (higher = higher priority)
    # @param name [Symbol] symbolic name for the source
    # @param options [Hash] additional source options
    def source(model, priority:, name:, **options)
      @sources << {
        model: model,
        priority: priority,
        name: name,
        options: options
      }
    end
  end

  # Configuration for field mappings
  class FieldsConfig
    def initialize(fields_hash)
      @fields = fields_hash
    end

    # Configure a field mapping
    # @param field_name [Symbol] name of the target field
    # @param options [Hash] field configuration options
    # @yield [FieldConfig] block for detailed field configuration
    def field(field_name, **options, &block)
      field_config = FieldConfig.new(field_name, options)
      field_config.instance_eval(&block) if block_given?
      @fields[field_name] = field_config
    end
  end

  # Configuration for a single field
  class FieldConfig
    attr_reader :name, :sources, :preference, :conflict_resolution, :transform, :validation

    def initialize(name, options = {})
      @name = name
      @sources = {}
      @preference = options[:preference]
      @conflict_resolution = options[:conflict_resolution] || :prefer_source
      @transform = options[:transform]
      @validation = options[:validation]
    end

    # Configure source mapping for this field
    # @param source_name [Symbol] name of the source
    # @param field [String] field name in the source
    # @param transform [Proc] transformation function
    # @param options [Hash] additional options
    def from(source_name, field: nil, transform: nil, **options)
      @sources[source_name] = {
        field: field || @name.to_s,
        transform: transform,
        options: options
      }
    end

    # Set preference for this field
    # @param source_name [Symbol] preferred source name
    def prefer(source_name)
      @preference = source_name
    end

    # Set conflict resolution strategy
    # @param strategy [Symbol] resolution strategy
    def resolve_conflicts(strategy)
      @conflict_resolution = strategy
    end

    # Set field transformation
    # @param proc [Proc] transformation function
    def transform(proc)
      @transform = proc
    end

    # Set field validation
    # @param proc [Proc] validation function
    def validate(proc)
      @validation = proc
    end
  end

  # Configuration for matching strategies
  class MatchingConfig
    attr_reader :strategy, :keys, :options

    def initialize
      @strategy = :exact
      @keys = []
      @options = {}
    end

    # Set matching strategy
    # @param strat [Symbol] matching strategy (:exact, :fuzzy, :composite, :custom)
    def strategy(strat)
      @strategy = strat
    end

    # Add a matching key configuration
    # @param fields [Array<Symbol>] fields to match on
    # @param exact [Boolean] use exact matching
    # @param fuzzy [Boolean] use fuzzy matching
    # @param threshold [Float] fuzzy matching threshold
    # @param required [Boolean] whether this key is required
    # @param fallback [Boolean] whether this is a fallback key
    def key(fields, exact: false, fuzzy: false, threshold: 0.8, required: true, fallback: false)
      key_strategy = if exact
                       :exact
                     elsif fuzzy
                       :fuzzy
                     else
                       :exact
                     end

      @keys << {
        fields: Array(fields),
        strategy: key_strategy,
        threshold: threshold,
        required: required,
        fallback: fallback
      }
    end

    # Set matching options
    # @param opts [Hash] matching options
    def options(opts)
      @options.merge!(opts)
    end

    # Validate matching configuration
    # @return [Array<String>] validation errors
    def validate
      errors = []
      errors << "No matching keys configured" if @keys.empty?
      
      @keys.each_with_index do |key, index|
        errors << "Key #{index} has no fields" if key[:fields].empty?
        if key[:strategy] == :fuzzy && (key[:threshold] < 0 || key[:threshold] > 1)
          errors << "Key #{index} fuzzy threshold must be between 0 and 1"
        end
      end

      errors
    end
  end

  # Configuration for hooks
  class HooksConfig
    attr_reader :pre_match, :post_match, :conflict_resolution, :validation, :pre_transform, :post_transform

    def initialize
      @pre_match = nil
      @post_match = nil
      @conflict_resolution = nil
      @validation = nil
      @pre_transform = nil
      @post_transform = nil
    end

    # Set pre-match hook
    # @param method_name [Symbol] method name to call
    def pre_match(method_name)
      @pre_match = method_name
    end

    # Set post-match hook
    # @param method_name [Symbol] method name to call
    def post_match(method_name)
      @post_match = method_name
    end

    # Set conflict resolution hook
    # @param method_name [Symbol] method name to call
    def conflict_resolution(method_name)
      @conflict_resolution = method_name
    end

    # Set validation hook
    # @param method_name [Symbol] method name to call
    def validation(method_name)
      @validation = method_name
    end

    # Set pre-transform hook
    # @param method_name [Symbol] method name to call
    def pre_transform(method_name)
      @pre_transform = method_name
    end

    # Set post-transform hook
    # @param method_name [Symbol] method name to call
    def post_transform(method_name)
      @post_transform = method_name
    end
  end
end