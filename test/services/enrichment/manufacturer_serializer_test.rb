# frozen_string_literal: true

require 'test_helper'

class Enrichment::ManufacturerSerializerTest < ActiveSupport::TestCase
  test 'serialises a manufacturer with its country' do
    result = Enrichment::ManufacturerSerializer.call(manufacturers(:boeing))

    assert_equal 'Boeing', result[:name]
    assert_equal 'BOE', result[:icao_code]
    assert_equal ['The Boeing Company'], result[:alt_names]
    assert_equal 'United States', result[:country][:name]
  end

  test 'defaults alt_names to an empty array when nil' do
    manufacturer = manufacturers(:boeing)
    manufacturer.alt_names = nil

    result = Enrichment::ManufacturerSerializer.call(manufacturer)

    assert_equal [], result[:alt_names]
  end

  test 'returns nil for a nil manufacturer' do
    assert_nil Enrichment::ManufacturerSerializer.call(nil)
  end
end
