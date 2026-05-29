# frozen_string_literal: true

require 'test_helper'

class EnrichmentRequestParserTest < ActiveSupport::TestCase
  test 'parses a JSON object into a symbolised hash' do
    result = Enrichment::RequestParser.parse('{"icao":"7C1469","include":["provenance"]}')

    assert_equal '7C1469', result[:icao]
    assert_equal ['provenance'], result[:include]
  end

  test 'raises BadRequestError for malformed JSON' do
    assert_raises(Enrichment::BadRequestError) do
      Enrichment::RequestParser.parse('{not json')
    end
  end

  test 'raises BadRequestError for a blank payload' do
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('') }
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse(nil) }
  end

  test 'raises BadRequestError when the payload is not a JSON object' do
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('"just a string"') }
    assert_raises(Enrichment::BadRequestError) { Enrichment::RequestParser.parse('[1,2,3]') }
  end
end
