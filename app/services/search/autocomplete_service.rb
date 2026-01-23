# frozen_string_literal: true

module Search
  # Provides autocomplete suggestions for field-specific search.
  #
  # Supports two modes:
  # 1. Field suggestions: Returns field names matching a prefix
  # 2. Value suggestions: Returns distinct values for a field from Meilisearch facets
  #
  # @example Field suggestions
  #   service = AutocompleteService.new('Aircraft')
  #   service.suggest_fields('man')
  #   # => [{ value: 'manufacturer', display: 'Manufacturer' }]
  #
  # @example Value suggestions
  #   service = AutocompleteService.new('Aircraft')
  #   service.suggest_values('manufacturer', 'Boe')
  #   # => [{ value: 'Boeing', hits: 150 }]
  class AutocompleteService
    # Maximum number of facet values to return.
    DEFAULT_VALUE_LIMIT = 10

    attr_reader :model_name

    # Creates a new autocomplete service for a model.
    #
    # @param model_name [String] The model class name
    def initialize(model_name)
      @model_name = model_name
    end

    # Returns field name suggestions matching the given prefix.
    # Delegates to FieldRegistry for static field definitions.
    #
    # @param prefix [String] The prefix to match
    # @return [Array<Hash>] Array of { value:, display: } hashes
    def suggest_fields(prefix)
      FieldRegistry.suggest_fields(model_name, prefix)
    end

    # Returns value suggestions for a specific field from Meilisearch facets.
    #
    # @param field_name [String] The user-facing field name
    # @param prefix [String] The value prefix to match
    # @param limit [Integer] Maximum number of suggestions
    # @return [Array<Hash>] Array of { value:, hits: } hashes
    def suggest_values(field_name, prefix, limit: DEFAULT_VALUE_LIMIT)
      meilisearch_attr = FieldRegistry.meilisearch_attribute_for(model_name, field_name)
      return [] unless meilisearch_attr

      begin
        model_class = model_name.constantize
        index = model_class.index

        # Use Meilisearch's facet search for efficient value lookup
        # This returns matching facet values with their document counts
        response = index.facet_search(meilisearch_attr, prefix)

        # Transform the response into our standard format
        response['facetHits']
          .take(limit)
          .map do |hit|
            {
              value: hit['value'],
              hits: hit['count']
            }
          end
      rescue StandardError => e
        # Log the error but return empty results rather than failing
        Rails.logger.error("AutocompleteService error for #{model_name}.#{field_name}: #{e.message}")
        []
      end
    end

    # Returns all available field names for the model.
    # Useful for populating initial autocomplete options.
    #
    # @return [Array<Hash>] Array of { value:, display: } hashes
    def all_fields
      # Use suggest_fields with empty prefix to get all fields
      FieldRegistry.suggest_fields(model_name, '')
    end
  end
end
