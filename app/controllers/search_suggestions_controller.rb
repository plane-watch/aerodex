# frozen_string_literal: true

# Provides autocomplete suggestions for field-specific search.
#
# This controller serves two types of suggestions:
# 1. Field suggestions - returns matching field names for a model
# 2. Value suggestions - returns matching values for a specific field from Meilisearch facets
#
# @example Field suggestions request
#   GET /search/suggestions?model=Aircraft&mode=field&prefix=man
#   # => [{ "value": "manufacturer", "display": "Manufacturer" }]
#
# @example Value suggestions request
#   GET /search/suggestions?model=Aircraft&mode=value&field=manufacturer&prefix=Boe
#   # => [{ "value": "Boeing", "hits": 150 }]
class SearchSuggestionsController < ApplicationController
  # Maximum number of suggestions to return per request.
  SUGGESTION_LIMIT = 20

  # GET /search/suggestions
  #
  # Params:
  #   model: The model name (e.g., 'Aircraft')
  #   mode: 'field' or 'value'
  #   field: Field name (required when mode is 'value')
  #   prefix: The search prefix
  def index
    validate_params!

    service = Search::AutocompleteService.new(params[:model])

    suggestions = case params[:mode]
                  when 'field'
                    service.suggest_fields(params[:prefix] || '')
                  when 'value'
                    service.suggest_values(params[:field], params[:prefix] || '', limit: SUGGESTION_LIMIT)
                  else
                    []
                  end

    render json: suggestions.take(SUGGESTION_LIMIT)
  end

  private

  # Validates that required parameters are present.
  #
  # @raise [ActionController::ParameterMissing] If required params are missing
  def validate_params!
    unless params[:model].present?
      render json: { error: 'model parameter is required' }, status: :bad_request
      return
    end

    unless Search::FieldRegistry.registered_models.include?(params[:model])
      render json: { error: "Unknown model: #{params[:model]}" }, status: :bad_request
      return
    end

    unless %w[field value].include?(params[:mode])
      render json: { error: 'mode must be "field" or "value"' }, status: :bad_request
      return
    end

    if params[:mode] == 'value' && params[:field].blank?
      render json: { error: 'field parameter is required for value mode' }, status: :bad_request
      nil
    end
  end
end
