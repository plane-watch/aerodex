# frozen_string_literal: true

module Enrichment
  # Serialises an Aircraft into the v2.enrich.aircraft response body's `aircraft`
  # object. The ICAO Mode-S hex is lower-cased on output for consistency with the
  # flight-tracking pipeline; `status` is the enum label; `registration_date` is
  # an ISO 8601 date string. The opt-in provenance block is added by the handler,
  # not here.
  class AircraftSerializer
    # @param aircraft [Aircraft]
    # @return [Hash]
    def self.call(aircraft)
      {
        icao: aircraft.icao&.downcase,
        registration: aircraft.registration,
        serial_number: aircraft.serial_number,
        manufacture_year: aircraft.manufacture_year,
        registration_date: aircraft.registration_date&.iso8601,
        owner: aircraft.owner,
        status: aircraft.status,
        model: aircraft.model,
        name: aircraft.aircraft_name,
        engine_count: aircraft.engine_count,
        engine_model: aircraft.engine_model,
        cabin_configuration: aircraft.cabin_configuration,
        type: AircraftTypeSerializer.call(aircraft.aircraft_type),
        operator: OperatorSerializer.call(aircraft.operator),
        registration_country: CountrySerializer.call(aircraft.registration_country)
      }
    end
  end
end
