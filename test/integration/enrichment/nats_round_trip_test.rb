# frozen_string_literal: true

require 'test_helper'
require 'nats/client'

# Proves the full NATS request/reply path end to end against a real nats-server.
# Skipped unless NATS_TEST_URL is set, so the default suite (and CI without a
# broker) stays green. To run it locally:
#   1. Start a broker:  nats-server  (or: docker run -p 4222:4222 nats)
#   2. NATS_TEST_URL=nats://127.0.0.1:4222 bin/rails test test/integration/enrichment/nats_round_trip_test.rb
class Enrichment::NatsRoundTripTest < ActiveSupport::TestCase
  setup do
    @url = ENV.fetch('NATS_TEST_URL', nil)
    skip 'set NATS_TEST_URL to run the NATS integration test' if @url.blank?

    # Subscribe directly (no queue group needed for a single responder in the test)
    # and reuse the dispatcher so we exercise the real subject routing.
    @responder = NATS.connect(@url)
    @dispatcher = Enrichment::Dispatcher.new
    @subscription = @responder.subscribe('v2.enrich.*') do |msg|
      Rails.application.executor.wrap { msg.respond(@dispatcher.dispatch(msg.subject, msg.data)) }
    end
    @responder.flush

    @client = NATS.connect(@url)
  end

  teardown do
    @subscription&.unsubscribe
    @responder&.close
    @client&.close
  end

  test 'request/reply returns the serialised aircraft' do
    response = @client.request('v2.enrich.aircraft', { icao: aircraft(:one).icao }.to_json, timeout: 2)
    body = JSON.parse(response.data)

    assert_equal true, body['found']
    assert_equal aircraft(:one).icao.downcase, body['aircraft']['icao']
  end

  test 'request/reply returns found:false for an unknown aircraft' do
    response = @client.request('v2.enrich.aircraft', { icao: 'ZZZZZZ' }.to_json, timeout: 2)

    assert_equal({ 'found' => false }, JSON.parse(response.data))
  end
end
