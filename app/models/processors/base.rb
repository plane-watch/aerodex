# frozen_string_literal: true

require_relative 'combiner_config'
require_relative 'data_combiner'

module Processors
  class Base
    # Legacy transform_field method - maintained for backward compatibility
    def self.transform_field(key, value)
      return nil if @transform_data[key].nil?

      {
        key: @transform_data[key][:field] || key,
        value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
      }
    end
    
    def self.get_source_from_url(url, request_type='GET', headers={})
      mock = true if Rails.env == 'test'

      connection = Excon.new(url, method: request_type, headers: headers, mock: mock)
      result = connection.request

      return unless result.status == 200

      result.body
    end

    def self.new_import_report(import_errors, records_processed)
      Source::SourceImportReport.create(import_errors: import_errors, importer_type: name, records_processed: records_processed,
                                success: true)
    end

    # Generic data combiner configuration and execution methods
    
    # Class variable to store combiner configuration
    @combiner_config = nil
    
    # Configure the generic data combiner using DSL
    # 
    # @yield [CombinerConfig] configuration object for DSL
    # @return [CombinerConfig] the configuration object
    #
    # Example:
    #   configure_combiner do |config|
    #     config.sources do
    #       source Source::ModelA, priority: 1, name: :source_a
    #       source Source::ModelB, priority: 2, name: :source_b
    #     end
    #     config.target_model ::TargetModel
    #     config.fields do
    #       field :name do
    #         from :source_a, field: 'name'
    #         from :source_b, field: 'company_name'
    #         prefer :source_a
    #       end
    #     end
    #   end
    def self.configure_combiner(&block)
      @combiner_config = CombinerConfig.new
      @combiner_config.instance_eval(&block) if block_given?
      @combiner_config
    end

    # Execute the generic data combiner
    #
    # @param config [CombinerConfig, nil] optional configuration override
    # @return [CombinerResult] result object with metrics and errors
    #
    # Example:
    #   result = MyProcessor.combine_sources_generic
    #   puts result.summary
    def self.combine_sources_generic(config = nil)
      config ||= @combiner_config
      
      unless config
        raise ArgumentError, "No combiner configuration found. Use configure_combiner to set up configuration."
      end
      
      # Validate configuration before processing
      errors = config.validate
      unless errors.empty?
        raise ArgumentError, "Configuration validation failed: #{errors.join(', ')}"
      end
      
      # Create and execute combiner
      combiner = DataCombiner.new(config, self)
      combiner.execute
    end

    # Get the current combiner configuration
    #
    # @return [CombinerConfig, nil] current configuration or nil if not set
    def self.combiner_config
      @combiner_config
    end

    # Helper method to check if combiner is configured
    #
    # @return [Boolean] true if combiner is configured
    def self.combiner_configured?
      !@combiner_config.nil?
    end

    # Execute data combination with transaction wrapper and error handling
    #
    # @param config [CombinerConfig, nil] optional configuration override
    # @return [CombinerResult] result object with metrics and errors
    def self.combine_sources_with_transaction(config = nil)
      result = nil
      
      ActiveRecord::Base.transaction do
        begin
          result = combine_sources_generic(config)
          
          # Check if there were critical errors that should rollback
          if result.total_errors > 0
            Rails.logger.warn "Data combination completed with #{result.total_errors} errors"
          end
          
        rescue StandardError => e
          Rails.logger.error "Data combination failed: #{e.message}"
          raise e
        end
      end
      
      result
    end

    # Backward compatibility method - delegates to existing combine_sources if present,
    # otherwise uses the generic combiner
    #
    # @param config [CombinerConfig, nil] optional configuration override
    # @return [CombinerResult, Object] result from combiner or existing method
    def self.combine_sources(config = nil)
      # Check if the subclass has its own combine_sources method
      if method_defined_in_subclass?(:combine_sources)
        # Call the original method if it exists
        super()
      elsif combiner_configured?
        # Use the generic combiner if configured
        combine_sources_generic(config)
      else
        raise NotImplementedError, "No combine_sources method or combiner configuration found"
      end
    end

    private

    # Check if a method is defined in a subclass (not in Base)
    def self.method_defined_in_subclass?(method_name)
      return false if self == Base
      
      # Check if the method is defined in this class specifically
      instance_methods(false).include?(method_name) || 
      singleton_methods(false).include?(method_name)
    end
  end
end
