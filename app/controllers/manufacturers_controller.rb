# frozen_string_literal: true

class ManufacturersController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @manufacturers = field_search(Manufacturer, params[:search], includes: [:country])

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'manufacturers/manufacturer', collection: @manufacturers) }
      format.html
    end
  end

  def show
    @manufacturer = Manufacturer.includes(:country).find(params[:id])
    @aircraft_types = @manufacturer.aircraft_types.order(:name)
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end
