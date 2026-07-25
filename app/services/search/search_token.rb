# frozen_string_literal: true

module Search
  # Represents a single parsed token from a search query string.
  #
  # Tokens can be one of several types:
  # - Field-qualified: `manufacturer:Boeing` or `manufacturer:Boeing*`
  # - Negated: `-manufacturer:Boeing` or `NOT manufacturer:Boeing`
  # - Free text: Unqualified search terms like `VH-OQA`
  # - Boolean operators: `AND` or `OR`
  #
  # @example Field-qualified token
  #   token = SearchToken.new(
  #     type: :field_value,
  #     field: 'manufacturer',
  #     value: 'Boeing',
  #     exact: true,
  #     negated: false
  #   )
  #   token.field_qualified?  # => true
  #   token.partial?          # => false
  #
  # @example Partial match token
  #   token = SearchToken.new(
  #     type: :field_value,
  #     field: 'manufacturer',
  #     value: 'Boe',
  #     exact: false,  # Partial match (value had * suffix)
  #     negated: false
  #   )
  #   token.partial?  # => true
  #
  # @example Negated token
  #   token = SearchToken.new(
  #     type: :field_value,
  #     field: 'manufacturer',
  #     value: 'Boeing',
  #     exact: true,
  #     negated: true
  #   )
  #   token.negated?  # => true
  class SearchToken
    # Valid token types that the parser can produce.
    VALID_TYPES = %i[
      field_value
      free_text
      boolean_and
      boolean_or
    ].freeze

    attr_reader :type, :field, :value, :exact, :negated

    # Creates a new search token.
    #
    # @param type [Symbol] The token type (see VALID_TYPES)
    # @param field [String, nil] The field name for field-qualified tokens
    # @param value [String, nil] The search value
    # @param exact [Boolean] Whether this is an exact match (false = partial/prefix match)
    # @param negated [Boolean] Whether this token is negated
    # @raise [ArgumentError] If the type is not valid
    def initialize(type:, field: nil, value: nil, exact: true, negated: false)
      validate_type!(type)

      @type = type
      @field = field&.downcase&.strip
      @value = value&.strip
      @exact = exact
      @negated = negated
    end

    # Returns true if this token specifies a field to search.
    #
    # @return [Boolean]
    def field_qualified?
      type == :field_value && field.present?
    end

    # Returns true if this is a partial (prefix) match.
    # Partial matches use the `*` suffix in the query syntax.
    #
    # @return [Boolean]
    def partial?
      !exact
    end

    # Returns true if this token should exclude matching results.
    #
    # @return [Boolean]
    def negated?
      negated
    end

    # Returns true if this is an exact match.
    #
    # @return [Boolean]
    def exact?
      exact
    end

    # Returns true if this is unqualified free text.
    #
    # @return [Boolean]
    def free_text?
      type == :free_text
    end

    # Returns true if this is a boolean operator.
    #
    # @return [Boolean]
    def boolean_operator?
      %i[boolean_and boolean_or].include?(type)
    end

    # Returns the display value for UI rendering.
    # Wraps exact values with spaces in quotes.
    #
    # @return [String]
    def display_value
      return value unless value&.include?(' ') && exact?

      %("#{value}")
    end

    # Returns a hash representation for JSON serialisation.
    #
    # @return [Hash]
    def to_h
      {
        type: type,
        field: field,
        value: value,
        exact: exact,
        negated: negated
      }
    end

    # Returns a JSON string representation.
    #
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Creates a SearchToken from a hash (for deserialisation).
    #
    # @param hash [Hash] The hash representation
    # @return [SearchToken]
    def self.from_h(hash)
      new(
        type: hash[:type]&.to_sym || hash['type']&.to_sym,
        field: hash[:field] || hash['field'],
        value: hash[:value] || hash['value'],
        exact: hash.fetch(:exact, hash.fetch('exact', true)),
        negated: hash.fetch(:negated, hash.fetch('negated', false))
      )
    end

    private

    # Validates that the token type is one of the allowed types.
    #
    # @param type [Symbol] The type to validate
    # @raise [ArgumentError] If the type is not valid
    def validate_type!(type)
      return if VALID_TYPES.include?(type)

      raise ArgumentError, "Invalid token type: #{type}. Must be one of: #{VALID_TYPES.join(', ')}"
    end
  end
end
