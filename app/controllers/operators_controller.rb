# frozen_string_literal: true

# Controller for the Operator Model
class OperatorsController < ApplicationController
  before_action :set_operator, only: [:show, :edit, :update, :destroy]

  def index
    q = Operator.pagy_search(params[:search])
    @pagy, @operators = pagy_meilisearch(q)

    respond_to do |format|
      format.turbo_stream { render_infinite_scroll(partial: 'operators/operator', collection: @operators) }
      format.html
    end
  end

  def show
  end

  def new
    @operator = Operator.new
  end

  def create
    @operator = Operator.new(operator_params)

    if @operator.save
      redirect_to @operator, notice: 'Operator was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @operator.update(operator_params)
      redirect_to @operator, notice: 'Operator was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @operator.destroy
    redirect_to operators_path, notice: 'Operator was successfully deleted.'
  end

  private

  def set_operator
    @operator = Operator.find(params[:id])
  end

  def operator_params
    params.require(:operator).permit(:name, :icao_code, :iata_code, :country_id)
  end

  def render_infinite_scroll(partial:, collection:)
    render turbo_stream: turbo_stream.append(
      params.fetch(:turbo_target, 'list'),
      partial: partial, collection: collection
    )
  end

end
