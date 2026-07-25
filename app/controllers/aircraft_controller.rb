class AircraftController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @aircraft = field_search(Aircraft, params[:search], includes: %i[aircraft_type operator])

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'aircraft/aircraft', collection: @aircraft) }
      format.html
    end
  end

  def show
    @aircraft = Aircraft.includes(:aircraft_type, :operator, :registration_country,
                                  manufacturer: :country).find(params[:id])
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end
