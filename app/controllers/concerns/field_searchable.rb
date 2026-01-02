# frozen_string_literal: true

# Provides field-specific search functionality for controllers.
#
# Include this concern in any controller that needs to support the advanced
# field:value search syntax. It handles parsing the search query, translating
# it to Meilisearch parameters, and storing parsed tokens for view rendering.
#
# @example Basic usage in a controller
#   class AircraftController < ApplicationController
#     include FieldSearchable
#
#     def index
#       @pagy, @aircraft = field_search(Aircraft, params[:search])
#     end
#   end
#
# @example Accessing parsed tokens in views
#   <% parsed_search_tokens.each do |token| %>
#     <span><%= token.field %>: <%= token.value %></span>
#   <% end %>
module FieldSearchable
  extend ActiveSupport::Concern

  included do
    helper_method :parsed_search_tokens if respond_to?(:helper_method)
  end

  private

  # Performs a field-aware search on the given model class.
  #
  # If the query contains field:value syntax, it parses and translates
  # the query into Meilisearch filter and search parameters. Otherwise,
  # it falls back to standard full-text search.
  #
  # @param model_class [Class] The ActiveRecord model to search
  # @param query [String] The raw search query from params
  # @param includes [Array, nil] Associations to eager load (optional)
  # @return [Array(Pagy, ActiveRecord::Relation)] Pagy metadata and results
  def field_search(model_class, query, includes: nil)
    # Apply includes if provided
    base_scope = includes ? model_class.includes(*includes) : model_class

    # No query - return all records
    return pagy(base_scope.all) if query.blank?

    # Parse the query into tokens
    parser = Search::QueryParser.new(query)
    tokens = parser.parse

    # Store for view access (chip display)
    @parsed_search_tokens = tokens

    if parser.has_field_qualifiers?
      # Has field:value tokens - use enhanced search
      perform_field_search(model_class, base_scope, tokens, parser)
    else
      # No field qualifiers - standard full-text search
      results = base_scope.pagy_search(query)
      pagy_meilisearch(results)
    end
  end

  # Returns the parsed search tokens for rendering in views.
  #
  # @return [Array<Search::SearchToken>]
  def parsed_search_tokens
    @parsed_search_tokens || []
  end

  # Default number of results per page.
  FIELD_SEARCH_PER_PAGE = 20

  # Performs the actual field-specific search.
  #
  # Queries Meilisearch directly via the index to avoid caching issues with
  # the meilisearch-rails gem when using filters.
  #
  # @param model_class [Class] The model class
  # @param base_scope [ActiveRecord::Relation] The base scope with includes
  # @param tokens [Array<Search::SearchToken>] The parsed tokens
  # @param parser [Search::QueryParser] The query parser
  # @return [Array(Pagy, ActiveRecord::Relation)]
  def perform_field_search(model_class, base_scope, tokens, parser)
    translator = Search::QueryTranslator.new(tokens, model_class.name)
    options = translator.to_meilisearch_options

    # Determine the main search query
    search_query = translator.search_query
    search_query = parser.free_text_query if search_query.blank?
    search_query = '' if search_query.blank?

    # Query Meilisearch directly via the index
    page = (params[:page] || 1).to_i
    ms_options = options.merge(limit: FIELD_SEARCH_PER_PAGE, offset: (page - 1) * FIELD_SEARCH_PER_PAGE)

    ms_response = model_class.index.search(search_query, ms_options)
    hits = ms_response['hits'] || []
    total_count = ms_response['estimatedTotalHits'] || hits.size

    # Extract IDs (Meilisearch returns strings, convert to integers)
    ids = hits.map { |hit| hit['id'].to_i }

    # Fetch records from database maintaining Meilisearch ordering
    if ids.any?
      records_by_id = base_scope.where(id: ids).index_by(&:id)
      records = ids.filter_map { |id| records_by_id[id] }
    else
      records = []
    end

    pagy = Pagy.new(count: total_count, page: page, limit: FIELD_SEARCH_PER_PAGE)

    [pagy, records]
  rescue StandardError => e
    Rails.logger.error("Field search error: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))

    # Fall back to basic full-text search
    results = base_scope.pagy_search(parser.free_text_query.presence || '')
    pagy_meilisearch(results)
  end
end
