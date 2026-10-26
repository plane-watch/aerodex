# frozen_string_literal: true

require 'test_helper'
require 'net/http'

class EnrichmentMetricsServerTest < ActiveSupport::TestCase
  test 'serves the Prometheus text exposition on /metrics' do
    # Record at least one observation so the output is non-empty.
    Enrichment::Metrics.observe(subject: 'v2.enrich.aircraft', result: 'hit', duration: 0.01)

    server = Enrichment::MetricsServer.new(port: 0) # port 0 = OS-assigned free port
    server.start
    begin
      response = Net::HTTP.get_response(URI("http://127.0.0.1:#{server.port}/metrics"))

      assert_equal '200', response.code
      assert_match(/aerodex_enrichment_requests_total/, response.body)
    ensure
      server.stop
    end
  end
end
