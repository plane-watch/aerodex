# frozen_string_literal: true

module Enrichment
  # Maps an exact NATS subject to its handler instance. The NATS server
  # subscribes to the `v2.enrich.*` wildcard, so messages for unknown subjects
  # under that wildcard reach the dispatcher and receive a bad_request reply
  # rather than timing out.
  class Dispatcher
    # Subject string => handler class.
    SUBJECTS = {
      'v2.enrich.aircraft' => AircraftHandler,
      'v2.enrich.route' => RouteHandler,
      'v2.enrich.airport' => AirportHandler
    }.freeze

    def initialize
      @handlers = SUBJECTS.transform_values(&:new)
    end

    # @param subject [String] The exact NATS subject of the message.
    # @param data [String, nil] The raw message payload.
    # @return [String] The JSON reply body.
    def dispatch(subject, data)
      handler = @handlers[subject]
      return unsupported(subject) unless handler

      handler.call(data)
    end

    private

    def unsupported(subject)
      { error: "unsupported subject: #{subject}", code: 'bad_request' }.to_json
    end
  end
end
