# frozen_string_literal: true

class AirportsController < ApplicationController
  def index
    q = Airport.pagy_search(params[:search])
    @pagy, @airports = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'airports/airport', collection: @airports) }
      format.html
    end
  end

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end