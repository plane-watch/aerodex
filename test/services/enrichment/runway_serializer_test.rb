# frozen_string_literal: true

require 'test_helper'

class EnrichmentRunwaySerializerTest < ActiveSupport::TestCase
  test 'serialises a runway, converting decimals to floats' do
    result = Enrichment::RunwaySerializer.call(airport_runways(:yssy_rwy_16r))

    assert_equal '16R', result[:name]
    assert_nil result[:le_ident]
    assert_nil result[:he_ident]
    assert_in_delta 167.85, result[:heading], 0.001
    assert_in_delta 3971.0, result[:length], 0.001
    assert_in_delta 45.0, result[:width], 0.001
    assert_equal false, result[:lighted]
    assert_equal false, result[:closed]
    assert_instance_of Float, result[:heading]
  end

  test 'leaves nil dimensions as nil' do
    runway = airport_runways(:yssy_rwy_16r)
    runway.heading = nil

    result = Enrichment::RunwaySerializer.call(runway)

    assert_nil result[:heading]
  end
end
