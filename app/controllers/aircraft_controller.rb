class AircraftController < ApplicationController
  def index
    @aircraft = Aircraft.all.limit(10)
  end
end
