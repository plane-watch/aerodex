class AircraftController < ApplicationController
  def index
    aircraft = Aircraft.includes(:aircraft_type, :operator).pagy_search(params[:search])
    @pagy, @aircraft = pagy_meilisearch(aircraft)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'aircraft/aircraft', collection: @aircraft) }
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
