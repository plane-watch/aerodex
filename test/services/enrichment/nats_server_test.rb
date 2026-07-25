# frozen_string_literal: true

require 'test_helper'

class EnrichmentNatsServerTest < ActiveSupport::TestCase
  # A stand-in for a nats-pure message: captures whatever the server responds.
  class FakeMessage
    attr_reader :subject, :data, :reply, :responses

    def initialize(subject:, data:, reply: '_INBOX.test')
      @subject = subject
      @data = data
      @reply = reply
      @responses = []
    end

    def respond(payload)
      @responses << payload
    end
  end

  setup { @server = Enrichment::NatsServer.new(url: 'nats://unused.invalid:4222') }

  test 'handle_message dispatches and responds with the serialised reply' do
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json)

    @server.send(:handle_message, message)

    assert_equal 1, message.responses.length
    assert_equal true, JSON.parse(message.responses.first)['found']
  end

  test 'handle_message records a hit metric' do
    before = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json)

    @server.send(:handle_message, message)

    after = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    assert_equal before + 1, after
  end

  test 'handle_message does not respond when there is no reply inbox' do
    message = FakeMessage.new(subject: 'v2.enrich.aircraft', data: { icao: aircraft(:one).icao }.to_json, reply: nil)

    @server.send(:handle_message, message)

    assert_empty message.responses
  end

  test 'subscribes to the v2.enrich wildcard under the default queue group' do
    assert_equal 'v2.enrich.*', Enrichment::NatsServer::SUBJECT_WILDCARD
    assert_equal 'aerodex-enrich-v2', Enrichment::NatsServer::DEFAULT_QUEUE_GROUP
  end

  # A stand-in for a nats-pure connection whose #drain is asynchronous, matching
  # the real client: it hands off to a background thread and returns at once,
  # firing the on_close callback only once the drain has finished.
  class FakeConnection
    DRAIN_DURATION = 0.2

    def on_close(&callback)
      @close_callback = callback
    end

    def drain
      Thread.new do
        sleep DRAIN_DURATION
        @close_callback&.call
      end
    end
  end

  # A metrics server that only records that it was stopped.
  class FakeMetricsServer
    attr_reader :stopped

    def stop
      @stopped = true
    end
  end

  test 'shutdown waits for the drain to finish before returning' do
    connection = FakeConnection.new
    metrics_server = FakeMetricsServer.new
    server = Enrichment::NatsServer.new(
      url: 'nats://unused.invalid:4222',
      metrics_server: metrics_server
    )
    # Wire the connection up exactly as #connect does.
    closed = server.instance_variable_get(:@closed)
    connection.on_close { closed.push(true) }
    server.instance_variable_set(:@nats, connection)

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.send(:shutdown)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_operator elapsed, :>=, FakeConnection::DRAIN_DURATION,
                    'shutdown returned before the drain had completed'
    assert metrics_server.stopped, 'the metrics server was not stopped'
  end
end
