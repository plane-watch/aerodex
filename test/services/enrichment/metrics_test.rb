# frozen_string_literal: true

require 'test_helper'

class EnrichmentMetricsTest < ActiveSupport::TestCase
  test 'records a request observation against the counter and histogram' do
    before = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })

    Enrichment::Metrics.observe(subject: 'v2.enrich.aircraft', result: 'hit', duration: 0.01)

    after = Enrichment::Metrics.requests.get(labels: { subject: 'v2.enrich.aircraft', result: 'hit' })
    assert_equal before + 1, after
  end

  test 'classify maps a reply body to a result label' do
    assert_equal 'hit', Enrichment::Metrics.classify('{"found":true}')
    assert_equal 'miss', Enrichment::Metrics.classify('{"found":false}')
    assert_equal 'bad_request', Enrichment::Metrics.classify('{"code":"bad_request"}')
    assert_equal 'error', Enrichment::Metrics.classify('{"code":"internal"}')
  end

  test 'increment_reconnects bumps the reconnect counter' do
    before = Enrichment::Metrics.reconnects.get
    Enrichment::Metrics.increment_reconnects
    assert_equal before + 1, Enrichment::Metrics.reconnects.get
  end
end
