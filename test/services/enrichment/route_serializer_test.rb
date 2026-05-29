# frozen_string_literal: true

require 'test_helper'

class Enrichment::RouteSerializerTest < ActiveSupport::TestCase
  test 'serialises a route with operator and ordered segments' do
    result = Enrichment::RouteSerializer.call(routes(:aa_1))

    assert_equal 'AA1', result[:callsign]
    assert_equal 'American Airlines', result[:operator][:name]
    assert_equal 2, result[:segments].length

    first = result[:segments].first
    assert_equal 1, first[:order]
    assert_equal '00:15:04', first[:departing_time]
    assert_equal '00:15:04', first[:arrival_time]
    assert_equal 'YSSY', first[:airport][:icao_code]
    assert_not first[:airport].key?(:runways) # uses the lean summary
  end

  test 'orders segments by their order column' do
    result = Enrichment::RouteSerializer.call(routes(:aa_1))

    orders = result[:segments].map { |segment| segment[:order] }
    assert_equal orders.sort, orders
  end
end
