class HomeController < ApplicationController
  def index
  end

  def dashboard
    @aircraft_count = Aircraft.count
    @aircraft_types_count = AircraftType.count
    @manufacturers_count = Manufacturer.count
    @airports_count = Airport.count
    @countries_count = Country.count
    @routes_count = Route.count
    @operators_count = Operator.count

    # Pending approvals widget
    @pending_batches = StagedBatch.pending.order(created_at: :desc).limit(5).includes(:created_by)
    @pending_count = StagedBatch.pending.count
  end
end