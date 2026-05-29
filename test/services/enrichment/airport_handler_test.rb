# frozen_string_literal: true

require 'test_helper'

class Enrichment::AirportHandlerTest < ActiveSupport::TestCase
  test 'returns found airport for a known ICAO' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ icao: 'YSSY' }.to_json))

    assert_equal true, reply['found']
    assert_equal 'YSSY', reply['airport']['icao_code']
    assert reply['airport']['runways'].any?
  end

  test 'returns found airport for a known IATA' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ iata: 'SYD' }.to_json))

    assert_equal 'YSSY', reply['airport']['icao_code']
  end

  test 'returns found:false for an unknown code' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({ icao: 'ZZZZ' }.to_json))

    assert_equal({ 'found' => false }, reply)
  end

  test 'returns bad_request when neither ICAO nor IATA is given' do
    reply = JSON.parse(Enrichment::AirportHandler.new.call({}.to_json))

    assert_equal 'bad_request', reply['code']
  end
end
