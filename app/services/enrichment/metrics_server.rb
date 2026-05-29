# frozen_string_literal: true

require 'webrick'
require 'prometheus/client/formats/text'

module Enrichment
  # A minimal HTTP server that exposes the enrichment service's Prometheus
  # metrics on /metrics. Runs WEBrick in a background thread so the main thread
  # stays free for the NATS subscription loop. Mirrors how the Go pw_atc_api
  # service exposed its own metrics port.
  class MetricsServer
    # Content type for the Prometheus text exposition format (version 0.0.4).
    CONTENT_TYPE = 'text/plain; version=0.0.4'
    # Default port; matches the Go service's monitoring port for consistency.
    DEFAULT_PORT = 9602

    # @param port [Integer] The port to listen on (0 selects a free OS port).
    def initialize(port: ENV.fetch('METRICS_PORT', DEFAULT_PORT).to_i)
      @configured_port = port
    end

    # Starts the server in a background thread. Returns once it is accepting
    # connections.
    def start
      @server = WEBrick::HTTPServer.new(
        Port: @configured_port,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      @server.mount_proc('/metrics') do |_request, response|
        response.content_type = CONTENT_TYPE
        response.body = Prometheus::Client::Formats::Text.marshal(Metrics.registry)
      end
      @thread = Thread.new { @server.start }
    end

    # The actual port the server bound to (useful when port 0 was requested).
    #
    # @return [Integer]
    def port
      @server.config[:Port]
    end

    # Stops the server and joins its thread.
    def stop
      @server&.shutdown
      @thread&.join
    end
  end
end
