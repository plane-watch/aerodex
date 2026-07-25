# frozen_string_literal: true

class AirportsController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @airports = field_search(Airport, params[:search], includes: [:country])

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'airports/airport', collection: @airports) }
      format.html
    end
  end

  def show
    @airport = Airport.includes(:country, :airport_runways).find(params[:id])
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end
