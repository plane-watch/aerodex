# frozen_string_literal: true

class RunwaysController < ApplicationController
  def index
    q = AirportRunway.pagy_search(params[:search])
    @pagy, @runways = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'runways/runway', collection: @runways) }
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