# frozen_string_literal: true

class CountriesController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @countries = field_search(Country, params[:search])

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