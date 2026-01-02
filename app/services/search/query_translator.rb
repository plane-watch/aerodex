# frozen_string_literal: true

module Search
  # Translates parsed search tokens into Meilisearch query parameters.
  #
  # Handles the complexity of converting user-friendly query syntax into
  # Meilisearch's filter and search parameters, including:
  # - Exact matching via filters
  # - Partial matching via attributesToSearchOn
  # - Boolean operators (AND/OR)
  # - Negation
  #
  # @example Basic usage
  #   parser = QueryParser.new('manufacturer:Boeing operator:Qantas')
  #   tokens = parser.parse
  #   translator = QueryTranslator.new(tokens, 'Aircraft')
  #
  #   translator.to_meilisearch_options
  #   # => {
  #   #   filter: 'aircraft_manufacturer = "Boeing" AND operator = "Qantas"'
  #   # }
  #
  # @example With partial matching
  #   parser = QueryParser.new('manufacturer:Boe*')
  #   tokens = parser.parse
  #   translator = QueryTranslator.new(tokens, 'Aircraft')
  #
  #   translator.search_query  # => 'Boe'
  #   translator.to_meilisearch_options
  #   # => {
  #   #   attributesToSearchOn: ['aircraft_manufacturer']
  #   # }
  class QueryTranslator
    attr_reader :tokens, :model_name

    # Default boolean operator when none is specified between tokens.
    DEFAULT_BOOLEAN_OPERATOR = 'AND'

    # Creates a new translator.
    #
    # @param tokens [Array<SearchToken>] The parsed tokens
    # @param model_name [String] The model being searched
    def initialize(tokens, model_name)
      @tokens = Array(tokens)
      @model_name = model_name
    end

    # Returns the main search query string for Meilisearch.
    # Combines free-text tokens and partial-match field values.
    #
    # @return [String]
    def search_query
      parts = []

      # Add free text (non-negated only; negated free text isn't supported by Meilisearch)
      tokens.select { |t| t.free_text? && !t.negated? }.each do |token|
        parts << token.value
      end

      # Add partial match values (these search via the main query, not filters)
      partial_tokens.each do |token|
        parts << token.value
      end

      parts.join(' ')
    end

    # Returns the Meilisearch options hash for the search.
    #
    # @return [Hash] Options to pass to Meilisearch search
    def to_meilisearch_options
      options = {}

      # Build filter string for exact matches
      filter = build_filter_string
      options[:filter] = filter if filter.present?

      # Limit search to specific attributes for partial matches
      if partial_tokens.any?
        attributes = partial_tokens.map do |token|
          FieldRegistry.meilisearch_attribute_for(model_name, token.field)
        end.compact.uniq

        options[:attributesToSearchOn] = attributes if attributes.any?
      end

      options
    end

    # Returns tokens that should use exact matching (via filters).
    #
    # @return [Array<SearchToken>]
    def exact_tokens
      @exact_tokens ||= tokens.select { |t| t.field_qualified? && t.exact? }
    end

    # Returns tokens that should use partial matching (via search query).
    #
    # @return [Array<SearchToken>]
    def partial_tokens
      @partial_tokens ||= tokens.select { |t| t.field_qualified? && t.partial? }
    end

    # Returns true if there are any valid field-qualified tokens.
    #
    # @return [Boolean]
    def has_field_filters?
      tokens.any? { |t| t.field_qualified? && valid_field?(t.field) }
    end

    private

    # Builds the Meilisearch filter string from exact-match tokens.
    #
    # @return [String, nil]
    def build_filter_string
      filter_parts = []
      current_operator = DEFAULT_BOOLEAN_OPERATOR

      tokens.each do |token|
        case token.type
        when :boolean_and
          current_operator = 'AND'
        when :boolean_or
          current_operator = 'OR'
        when :field_value
          next unless token.exact?
          next unless valid_field?(token.field)

          filter_expr = build_filter_expression(token)
          next unless filter_expr

          if filter_parts.any?
            filter_parts << current_operator
            current_operator = DEFAULT_BOOLEAN_OPERATOR
          end

          filter_parts << filter_expr
        end
      end

      return nil if filter_parts.empty?

      filter_parts.join(' ')
    end

    # Builds a single filter expression for a token.
    #
    # @param token [SearchToken] The token to convert
    # @return [String, nil]
    def build_filter_expression(token)
      meilisearch_attr = FieldRegistry.meilisearch_attribute_for(model_name, token.field)
      return nil unless meilisearch_attr

      # Escape double quotes in the value
      escaped_value = token.value.to_s.gsub('"', '\\"')

      if token.negated?
        # Negated filter: NOT attribute = "value"
        %(NOT #{meilisearch_attr} = "#{escaped_value}")
      else
        # Positive filter: attribute = "value"
        %(#{meilisearch_attr} = "#{escaped_value}")
      end
    end

    # Checks if a field name is valid for the current model.
    #
    # @param field_name [String] The field name to check
    # @return [Boolean]
    def valid_field?(field_name)
      FieldRegistry.valid_field?(model_name, field_name)
    end
  end
end
