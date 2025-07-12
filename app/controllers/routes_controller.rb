# frozen_string_literal: true

class RoutesController < ApplicationController
  def index
    q = Route.pagy_search(params[:search])
    @pagy, @routes = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'routes/route', collection: @routes) }
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