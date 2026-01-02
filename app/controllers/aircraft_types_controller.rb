# frozen_string_literal: true

class AircraftTypesController < ApplicationController
  include FieldSearchable

  def index
    @pagy, @aircraft_types = field_search(AircraftType, params[:search], includes: [:manufacturer])

    respond_to do |format|
      format.turbo_stream do
        render_infinite_scroll(partial: 'aircraft_types/aircraft_type', collection: @aircraft_types)
      end
      format.html
    end
  end

  def show
    @aircraft_type = AircraftType.includes(:manufacturer).find(params[:id])
    @pagy, @aircraft = pagy(@aircraft_type.aircraft.includes(:operator, :registration_country).order(:registration))
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end
