# frozen_string_literal: true

require 'test_helper'

class Enrichment::DispatcherTest < ActiveSupport::TestCase
  setup { @dispatcher = Enrichment::Dispatcher.new }

  test 'routes a known subject to its handler' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.aircraft', { icao: aircraft(:one).icao }.to_json))

    assert_equal true, reply['found']
  end

  test 'routes the airport subject to its handler' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.airport', { icao: 'YSSY' }.to_json))

    assert_equal 'YSSY', reply['airport']['icao_code']
  end

  test 'returns a bad_request reply for an unsupported subject' do
    reply = JSON.parse(@dispatcher.dispatch('v2.enrich.unknown', '{}'))

    assert_equal 'bad_request', reply['code']
    assert_match(/unsupported subject/, reply['error'])
  end

  test 'exposes the set of supported subjects' do
    assert_equal %w[v2.enrich.aircraft v2.enrich.route v2.enrich.airport].sort,
                 Enrichment::Dispatcher::SUBJECTS.keys.sort
  end
end
