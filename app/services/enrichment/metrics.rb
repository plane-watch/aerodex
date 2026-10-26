# frozen_string_literal: true

require 'prometheus/client'

module Enrichment
  # Prometheus instrumentation for the enrichment service. Metrics are registered
  # lazily against a dedicated registry (memoised) so the definitions are created
  # exactly once per process. The runner process is single-OS-process, so a plain
  # registry is sufficient (no multiprocess directory needed).
  module Metrics
    module_function

    # The metric label applied to successful lookups.
    RESULT_HIT = 'hit'
    # The metric label applied to lookup misses.
    RESULT_MISS = 'miss'
    # The metric label applied to malformed/invalid requests.
    RESULT_BAD_REQUEST = 'bad_request'
    # The metric label applied to internal failures.
    RESULT_ERROR = 'error'

    # Histogram buckets in seconds, tuned for fast indexed DB lookups.
    DURATION_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1].freeze

    def registry
      @registry ||= Prometheus::Client::Registry.new
    end

    def requests
      @requests ||= registry.counter(
        :aerodex_enrichment_requests_total,
        docstring: 'Total enrichment requests handled, by subject and result.',
        labels: %i[subject result]
      )
    end

    def request_duration
      @request_duration ||= registry.histogram(
        :aerodex_enrichment_request_duration_seconds,
        docstring: 'Enrichment request handler duration in seconds, by subject.',
        labels: %i[subject],
        buckets: DURATION_BUCKETS
      )
    end

    def reconnects
      @reconnects ||= registry.counter(
        :aerodex_enrichment_nats_reconnects_total,
        docstring: 'Total NATS reconnects observed by the enrichment service.'
      )
    end

    def in_flight
      @in_flight ||= registry.gauge(
        :aerodex_enrichment_in_flight,
        docstring: 'Enrichment requests currently being processed, by subject.',
        labels: %i[subject]
      )
    end

    # Records a completed request.
    #
    # @param subject [String]
    # @param result [String] One of the RESULT_* labels.
    # @param duration [Float] Handler duration in seconds.
    def observe(subject:, result:, duration:)
      requests.increment(labels: { subject: subject, result: result })
      request_duration.observe(duration, labels: { subject: subject })
    end

    # Increments the reconnect counter.
    def increment_reconnects
      reconnects.increment
    end

    # Derives the result label from a JSON reply body. Falls back to 'error' for
    # anything unparseable.
    #
    # @param reply [String] The JSON reply body.
    # @return [String] One of the RESULT_* labels.
    def classify(reply)
      parsed = JSON.parse(reply)
      case parsed['code']
      when 'bad_request' then RESULT_BAD_REQUEST
      when 'internal' then RESULT_ERROR
      else
        parsed['found'] == true ? RESULT_HIT : RESULT_MISS
      end
    rescue JSON::ParserError
      RESULT_ERROR
    end
  end
end
