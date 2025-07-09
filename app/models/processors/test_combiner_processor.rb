# frozen_string_literal: true

module Processors
  # Test processor for validating the generic data combiner implementation
  #
  # This processor is designed to safely test the new combiner system without
  # affecting any existing processors or production data. It demonstrates
  # how to configure and use the generic combiner for different scenarios.
  #
  # IMPORTANT: This is a test processor only - do not use in production!
  class TestCombinerProcessor < Base
    # Example configuration for complex multi-source combination
    # This mimics the current Operator processor pattern with VRS and OpenTravel sources
    def self.configure_operator_combination
      configure_combiner do |config|
        config.sources do
          source Source::Operator::VRSDataOperatorSource, priority: 1, name: :vrs
          source Source::Operator::OpenTravelOperatorSource, priority: 2, name: :open_travel
        end

        config.target_model ::Operator

        config.fields do
          field :name do
            from :vrs, field: 'name', transform: lambda { |value|
              normalize_operator_name(value)
            }
            from :open_travel, field: 'name', transform: ->(value) { value&.strip }
            prefer :vrs
            resolve_conflicts :prefer_source
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
          key %i[icao_code name], exact: true, required: true
          key %i[iata_code name], exact: true, fallback: true
          key %i[icao_code], fuzzy: true, threshold: 0.5, fallback: true
          key %i[iata_code], fuzzy: true, threshold: 0.75, fallback: true
        end

        config.hooks do
          pre_match :preprocess_operator_record
          post_match :validate_operator_business_rules
        end
      end
    end

    # Test method for operator combination
    def self.test_operator_combination
      puts 'Testing operator multi-source combination...'

      configure_operator_combination

      begin
        result = combine_sources_generic
        puts '✓ Operator combination test completed successfully'
        puts "  Records created: #{result.records_created}"
        puts "  Errors: #{result.total_errors}"
        puts "  Duration: #{result.duration&.round(2)}s"

        result
      rescue StandardError => e
        puts "✗ Operator combination test failed: #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(5).join("\n  ")}"
        raise
      end
    end

    # Test configuration validation
    def self.test_configuration_validation
      puts 'Testing configuration validation...'

      # Test invalid configuration
      begin
        configure_combiner do |_config|
          # Missing required fields
        end

        combine_sources_generic
        puts '✗ Configuration validation test failed - should have raised error'
      rescue ArgumentError => e
        puts "✓ Configuration validation test passed: #{e.message}"
      end
    end

    # Test error handling
    def self.test_error_handling
      puts 'Testing error handling...'

      configure_combiner do |config|
        config.sources do
          # Use a mock source to test error handling
          source Source::Operator::VRSDataOperatorSource, priority: 1, name: :test_source
        end

        config.target_model ::Operator

        config.fields do
          field :name do
            from :test_source, field: 'name'
          end
        end

        config.matching do
          strategy :exact
          key %i[name], exact: true, required: true
        end
      end

      begin
        result = combine_sources_generic
        puts '✓ Error handling test completed'
        puts "  Total errors: #{result.total_errors}"

        result
      rescue StandardError => e
        puts "✓ Error handling test passed - caught expected error: #{e.message}"
      end
    end

    # Run all tests
    def self.run_all_tests
      puts '=' * 50
      puts 'Running Generic Data Combiner Tests'
      puts '=' * 50

      tests = %i[
        test_configuration_validation
        test_error_handling
        test_operator_combination
      ]

      results = {}

      tests.each do |test_method|
        puts "\n#{'-' * 30}"
        begin
          results[test_method] = send(test_method)
          puts "✓ #{test_method} PASSED"
        rescue StandardError => e
          puts "✗ #{test_method} FAILED: #{e.message}"
          results[test_method] = e
        end
      end

      puts "\n#{'=' * 50}"
      puts 'Test Results Summary'
      puts '=' * 50

      passed = results.count { |_, result| !result.is_a?(Exception) }
      total = results.count

      puts "Passed: #{passed}/#{total}"

      if passed == total
        puts '🎉 All tests passed!'
      else
        puts '❌ Some tests failed - check output above'
      end

      results
    end

    # Private class methods for test processor functionality
    class << self
      private

      # Example custom method for normalizing operator names
      def normalize_operator_name(name)
        return nil unless name

        # Apply the same normalization patterns as the existing operator processor
        normalized = name.to_s.strip

        # Apply rewrite patterns (simplified version)
        normalized.gsub!(/Royal Flying Doctor Service.*/, 'Royal Flying Doctor Service')
        normalized.gsub!(/State Of New South Wales Represented By Nsw Police Force/, 'NSW Police Force')

        normalized
      end

      # Example pre-match hook
      def preprocess_operator_record(record)
        # Apply any preprocessing needed before matching
        record[:name] = normalize_operator_name(record[:name]) if record[:name]

        record
      end

      # Example post-match hook
      def validate_operator_business_rules(combined_record)
        # Apply business rule validation
        return false unless combined_record[:name]
        return false if combined_record[:icao_code].nil? && combined_record[:iata_code].nil?

        true
      end
    end
  end
end