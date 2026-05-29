# frozen_string_literal: true

require 'test_helper'

class EnrichmentRouteHandlerTest < ActiveSupport::TestCase
  test 'returns found route for a known callsign' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({ callsign: 'AA1' }.to_json))

    assert_equal true, reply['found']
    assert_equal 'AA1', reply['route']['callsign']
  end

  test 'returns found:false for an unknown callsign' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({ callsign: 'ZZ999' }.to_json))

    assert_equal({ 'found' => false }, reply)
  end

  test 'returns bad_request when callsign is missing' do
    reply = JSON.parse(Enrichment::RouteHandler.new.call({}.to_json))

    assert_equal 'bad_request', reply['code']
  end
end
