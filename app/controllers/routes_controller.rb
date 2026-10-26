# frozen_string_literal: true

class RoutesController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @routes = field_search(Route, params[:search], includes: [:operator])

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'routes/route', collection: @routes) }
      format.html
    end
  end

  def show
    @route = Route.includes(:operator, route_segments: :airport).find(params[:id])
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end
