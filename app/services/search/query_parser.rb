# frozen_string_literal: true

module Search
  # Parses a search query string into structured tokens.
  #
  # Supports the following query syntax:
  # - `field:value` - Exact match on a specific field
  # - `field:value*` - Partial (prefix) match on a specific field
  # - `field:"quoted value"` - Exact match with spaces
  # - `-field:value` - Negation (exclude matches)
  # - `NOT field:value` - Alternative negation syntax
  # - `field:a AND field:b` - Boolean AND (default between pairs)
  # - `field:a OR field:b` - Boolean OR
  # - Unqualified terms - Full-text search across all fields
  #
  # @example Basic parsing
  #   parser = QueryParser.new('manufacturer:Boeing operator:Qantas')
  #   tokens = parser.parse
  #   tokens.length  # => 2
  #   tokens.first.field  # => 'manufacturer'
  #   tokens.first.value  # => 'Boeing'
  #
  # @example Partial matching
  #   parser = QueryParser.new('manufacturer:Boe*')
  #   tokens = parser.parse
  #   tokens.first.partial?  # => true
  #
  # @example Mixed query
  #   parser = QueryParser.new('manufacturer:Boeing VH-OQA')
  #   tokens = parser.parse
  #   # Returns two tokens: one field-qualified, one free-text
  class QueryParser
    # Regular expression for matching field:value pairs.
    # Captures:
    # - negation prefix (-) if present
    # - field name (lowercase letters and underscores)
    # - quoted value OR unquoted value
    FIELD_VALUE_PATTERN = /
      (?<negation>-)?                     # Optional negation prefix
      (?<field>[a-z_]+)                   # Field name (lowercase, underscores allowed)
      :                                    # Colon separator
      (?:
        "(?<quoted_value>[^"]*)"          # Quoted value (allows spaces)
        |
        (?<unquoted_value>[^\s"]+)        # Unquoted value (no spaces)
      )
    /xi

    # Boolean operators that can combine field:value pairs.
    BOOLEAN_AND = 'AND'
    BOOLEAN_OR = 'OR'
    BOOLEAN_NOT = 'NOT'

    # All recognised boolean keywords.
    BOOLEAN_KEYWORDS = [BOOLEAN_AND, BOOLEAN_OR, BOOLEAN_NOT].freeze

    # Token type produced by each standalone boolean keyword. NOT is absent
    # because it is a negation prefix applied to the following token rather
    # than a token in its own right.
    BOOLEAN_TOKEN_TYPES = {
      BOOLEAN_AND => :boolean_and,
      BOOLEAN_OR => :boolean_or
    }.freeze

    attr_reader :query

    # Creates a new parser for the given query string.
    #
    # @param query [String] The raw search query
    def initialize(query)
      @query = query.to_s.strip
    end

    # Parses the query string into an array of tokens.
    #
    # @return [Array<SearchToken>] The parsed tokens
    def parse
      return [] if query.blank?

      tokens = []
      remaining = query.dup
      pending_negation = false

      while remaining.present?
        remaining = remaining.lstrip

        # Check for boolean operators first
        if (boolean_match = remaining.match(/\A(AND|OR|NOT)\b/i))
          keyword = boolean_match[1].upcase

          if keyword == BOOLEAN_NOT
            # NOT is a negation prefix for the next token
            pending_negation = true
          else
            # AND/OR are standalone boolean operators
            tokens << SearchToken.new(type: BOOLEAN_TOKEN_TYPES.fetch(keyword))
          end

          remaining = remaining[boolean_match[0].length..].to_s
          next
        end

        # Check for field:value pattern
        if (field_match = remaining.match(/\A#{FIELD_VALUE_PATTERN}/))
          value = field_match[:quoted_value] || field_match[:unquoted_value]
          is_negated = field_match[:negation].present? || pending_negation

          # Check for partial match suffix (*)
          is_partial = value.end_with?('*')
          value = value.chomp('*') if is_partial

          tokens << SearchToken.new(
            type: :field_value,
            field: field_match[:field],
            value: value,
            exact: !is_partial,
            negated: is_negated
          )

          pending_negation = false
          remaining = remaining[field_match[0].length..].to_s
          next
        end

        # Handle quoted free text
        if (quoted_match = remaining.match(/\A"([^"]*)"/))
          tokens << SearchToken.new(
            type: :free_text,
            value: quoted_match[1],
            negated: pending_negation
          )

          pending_negation = false
          remaining = remaining[quoted_match[0].length..].to_s
          next
        end

        # Handle unquoted free text (single word)
        if (word_match = remaining.match(/\A(\S+)/))
          word = word_match[1]

          # Skip if it looks like an incomplete field: pattern
          unless word.end_with?(':')
            tokens << SearchToken.new(
              type: :free_text,
              value: word,
              negated: pending_negation
            )
          end

          pending_negation = false
          remaining = remaining[word_match[0].length..].to_s
          next
        end

        # Safety: advance by one character if nothing matched
        remaining = remaining[1..].to_s
      end

      tokens
    end

    # Returns only the field-qualified tokens from the parsed query.
    #
    # @return [Array<SearchToken>]
    def field_tokens
      parse.select(&:field_qualified?)
    end

    # Returns only the free-text tokens from the parsed query.
    #
    # @return [Array<SearchToken>]
    def free_text_tokens
      parse.select(&:free_text?)
    end

    # Combines all free-text token values into a single search string.
    #
    # @return [String]
    def free_text_query
      free_text_tokens.map(&:value).join(' ')
    end

    # Returns true if the query contains any field-qualified tokens.
    #
    # @return [Boolean]
    def has_field_qualifiers?
      parse.any?(&:field_qualified?)
    end
  end
end
