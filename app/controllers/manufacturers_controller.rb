# frozen_string_literal: true

class ManufacturersController < ApplicationController
  def index
    if params[:search].present?
      q = Manufacturer.pagy_search(params[:search])
      @pagy, @manufacturers = pagy_meilisearch(q)
    else
      @pagy, @manufacturers = pagy(Manufacturer.all)
    end

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'manufacturers/manufacturer', collection: @manufacturers) }
      format.html
    end
  end

  def show
    @manufacturer = Manufacturer.includes(:country).find(params[:id])
  end

  private

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end
end