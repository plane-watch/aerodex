# frozen_string_literal: true

require 'test_helper'

class Enrichment::RouteQueryTest < ActiveSupport::TestCase
  test 'finds a route by callsign case-insensitively' do
    expected = routes(:aa_1)

    assert_equal expected, Enrichment::RouteQuery.call('aa1')
    assert_equal expected, Enrichment::RouteQuery.call('AA1')
  end

  test 'returns nil for an unknown callsign' do
    assert_nil Enrichment::RouteQuery.call('ZZ999')
  end

  test 'returns nil for a blank callsign' do
    assert_nil Enrichment::RouteQuery.call(nil)
  end
end
