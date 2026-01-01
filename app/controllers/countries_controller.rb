# frozen_string_literal: true

class CountriesController < ApplicationController
  def index
    if params[:search].present?
      q = Country.pagy_search(params[:search])
      @pagy, @countries = pagy_meilisearch(q)
    else
      @pagy, @countries = pagy(Country.all)
    end

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'countries/country', collection: @countries) }
      format.html
    end
  end

  def show
    @country = Country.find(params[:id])
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end