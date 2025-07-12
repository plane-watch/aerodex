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
  end
end