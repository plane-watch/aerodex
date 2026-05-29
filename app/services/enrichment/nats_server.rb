# frozen_string_literal: true

require 'nats/client'

module Enrichment
  # The long-lived NATS consumer for the enrichment service. Connects to NATS,
  # subscribes to the v2.enrich.* wildcard under a queue group (so work is
  # load-balanced across replicas), and dispatches each message to a handler.
  #
  # Each message is processed inside Rails.application.executor.wrap so that the
  # ActiveRecord connection used by the handler is checked out from, and returned
  # to, the connection pool correctly — essential because handlers run on
  # nats-pure's callback thread pool.
  #
  # Lifecycle: #run connects, subscribes, starts the metrics server, then blocks
  # until a SIGTERM/SIGINT triggers a graceful drain.
  class NatsServer
    # The wildcard subject covering every v2 enrichment subject.
    SUBJECT_WILDCARD = 'v2.enrich.*'
    # The queue group; all replicas share it so each request is handled once.
    DEFAULT_QUEUE_GROUP = 'aerodex-enrich-v2'

    # @param url [String, nil] The NATS server URL (defaults to NATS_URL).
    # @param queue_group [String] The queue group name.
    # @param metrics_server [MetricsServer] The metrics exposition server.
    def initialize(
      url: ENV.fetch('NATS_URL', nil),
      queue_group: ENV.fetch('NATS_QUEUE_GROUP', DEFAULT_QUEUE_GROUP),
      metrics_server: MetricsServer.new
    )
      @url = url
      @queue_group = queue_group
      @metrics_server = metrics_server
      @dispatcher = Dispatcher.new
      @stop = Queue.new
    end

    # Connects, subscribes and blocks until signalled to shut down, then drains.
    def run
      connect
      subscribe
      @metrics_server.start
      install_signal_traps
      Rails.logger.info(
        "[enrichment] subscribed to #{SUBJECT_WILDCARD} (queue=#{@queue_group}); waiting for requests"
      )
      @stop.pop # block until a signal pushes onto the stop queue
      shutdown
    end

    private

    def connect
      @nats = NATS.connect(@url)
      @nats.on_reconnect { Metrics.increment_reconnects }
      @nats.on_error { |error| Rails.logger.error("[enrichment] NATS error: #{error.class}: #{error.message}") }
    end

    def subscribe
      @subscription = @nats.subscribe(SUBJECT_WILDCARD, queue: @queue_group) do |msg|
        handle_message(msg)
      end
    end

    # Processes a single message: dispatch, respond, and record metrics. Wrapped
    # in the Rails executor for correct connection and reloader handling.
    #
    # @param msg [#subject, #data, #reply, #respond]
    def handle_message(msg)
      Rails.application.executor.wrap do
        Metrics.in_flight.increment(labels: { subject: msg.subject })
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        reply = @dispatcher.dispatch(msg.subject, msg.data)
        msg.respond(reply) if msg.reply

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        Metrics.observe(subject: msg.subject, result: Metrics.classify(reply), duration: duration)
      ensure
        Metrics.in_flight.decrement(labels: { subject: msg.subject })
      end
    rescue StandardError => e
      # A failure here means the executor or metrics raised, not a handler error
      # (handlers rescue internally). Log and continue serving.
      Rails.logger.error("[enrichment] message handling failed: #{e.class}: #{e.message}")
    end

    def install_signal_traps
      %w[TERM INT].each do |signal|
        Signal.trap(signal) { @stop.push(signal) }
      end
    end

    # Drains the subscription so in-flight requests finish and their replies are
    # flushed, then stops the metrics server.
    def shutdown
      Rails.logger.info('[enrichment] draining NATS connection')
      @nats&.drain
      @metrics_server.stop
      Rails.logger.info('[enrichment] shut down cleanly')
    end
  end
end
