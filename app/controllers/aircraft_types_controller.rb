# frozen_string_literal: true

class AircraftTypesController < ApplicationController
  def index
    q = AircraftType.pagy_search(params[:search])
    @pagy, @aircraft_types = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream do
        render_infinite_scroll(partial: 'aircraft_types/aircraft_type', collection: @aircraft_types)
      end
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
