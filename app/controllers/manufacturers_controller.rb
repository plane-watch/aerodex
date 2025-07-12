# frozen_string_literal: true

class ManufacturersController < ApplicationController
  def index
    q = Manufacturer.pagy_search(params[:search])
    @pagy, @manufacturers = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'manufacturers/manufacturer', collection: @manufacturers) }
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