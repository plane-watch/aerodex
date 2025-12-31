# frozen_string_literal: true

require 'test_helper'

class OperatorNameCanonicalisationTest < ActiveSupport::TestCase
  # Create a test class that extends the concern for testing
  class TestCanonicaliser
    extend OperatorNameCanonicalisation
  end

  # ==========================================================================
  # Tests for canonical_name_key
  # ==========================================================================

  test 'canonical_name_key returns empty string for blank input' do
    assert_equal '', TestCanonicaliser.canonical_name_key(nil)
    assert_equal '', TestCanonicaliser.canonical_name_key('')
    assert_equal '', TestCanonicaliser.canonical_name_key('   ')
  end

  test 'canonical_name_key strips corporate suffixes' do
    # All should produce the same key
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways')
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways Ltd')
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways Ltd.')
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways Limited')
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways Pty Ltd')
    assert_equal 'qantasairways', TestCanonicaliser.canonical_name_key('Qantas Airways Pty. Ltd.')
  end

  test 'canonical_name_key handles various corporate suffix formats' do
    # US formats
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines Inc')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines Inc.')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines Incorporated')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines LLC')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines L.L.C.')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines Corp')
    assert_equal 'deltaairlines', TestCanonicaliser.canonical_name_key('Delta Airlines Corporation')

    # German formats
    assert_equal 'lufthansa', TestCanonicaliser.canonical_name_key('Lufthansa GmbH')
    assert_equal 'lufthansa', TestCanonicaliser.canonical_name_key('Lufthansa AG')

    # French/Spanish formats
    assert_equal 'airfrance', TestCanonicaliser.canonical_name_key('Air France S.A.')
    assert_equal 'iberia', TestCanonicaliser.canonical_name_key('Iberia S.A.')
  end

  test 'canonical_name_key normalises spacing and hyphens' do
    # Same key regardless of spacing
    assert_equal 'jetkontor', TestCanonicaliser.canonical_name_key('Jet Kontor')
    assert_equal 'jetkontor', TestCanonicaliser.canonical_name_key('Jetkontor')
    assert_equal 'jetkontor', TestCanonicaliser.canonical_name_key('Jet-Kontor')
  end

  test 'canonical_name_key is case insensitive' do
    # "PTY LTD" is stripped as a corporate suffix
    assert_equal 'heliway', TestCanonicaliser.canonical_name_key('HELIWAY PTY LTD')
    assert_equal 'heliway', TestCanonicaliser.canonical_name_key('Heliway')
    assert_equal 'heliway', TestCanonicaliser.canonical_name_key('heliway')
  end

  test 'canonical_name_key removes punctuation' do
    assert_equal 'testagencies', TestCanonicaliser.canonical_name_key("Test Agencies!")
    # "Co." and "Company" are stripped as corporate suffixes
    assert_equal 'test', TestCanonicaliser.canonical_name_key('Test & Co.')
    assert_equal 'test', TestCanonicaliser.canonical_name_key('Test Company')
    # Non-suffix words are kept
    assert_equal 'testenterprise', TestCanonicaliser.canonical_name_key('Test Enterprise')
  end

  # ==========================================================================
  # Tests for aggressive_canonical_key
  # ==========================================================================

  test 'aggressive_canonical_key strips common airline terms' do
    # All should produce the same key
    assert_equal 'qantas', TestCanonicaliser.aggressive_canonical_key('Qantas')
    assert_equal 'qantas', TestCanonicaliser.aggressive_canonical_key('Qantas Airways')
    assert_equal 'qantas', TestCanonicaliser.aggressive_canonical_key('Qantas Airlines')
    assert_equal 'qantas', TestCanonicaliser.aggressive_canonical_key('Qantas Aviation')
  end

  test 'aggressive_canonical_key strips helicopter terms' do
    assert_equal 'pacific', TestCanonicaliser.aggressive_canonical_key('Pacific Helicopters')
    assert_equal 'pacific', TestCanonicaliser.aggressive_canonical_key('Pacific Heli Services')
  end

  # ==========================================================================
  # Tests for name_quality_score
  # ==========================================================================

  test 'name_quality_score returns 0 for blank input' do
    assert_equal 0, TestCanonicaliser.name_quality_score(nil)
    assert_equal 0, TestCanonicaliser.name_quality_score('')
  end

  test 'name_quality_score strongly prefers operators with ICAO code' do
    score_with_icao = TestCanonicaliser.name_quality_score('Qantas', has_icao: true)
    score_without = TestCanonicaliser.name_quality_score('Qantas', has_icao: false)

    assert_operator score_with_icao, :>, score_without + 100
  end

  test 'name_quality_score prefers operators with IATA code' do
    score_with_iata = TestCanonicaliser.name_quality_score('Qantas', has_iata: true)
    score_without = TestCanonicaliser.name_quality_score('Qantas', has_iata: false)

    assert_operator score_with_iata, :>, score_without
  end

  test 'name_quality_score penalises ALL CAPS names' do
    score_caps = TestCanonicaliser.name_quality_score('QANTAS AIRWAYS')
    score_proper = TestCanonicaliser.name_quality_score('Qantas Airways')

    assert_operator score_proper, :>, score_caps
  end

  test 'name_quality_score prefers longer descriptive names' do
    score_long = TestCanonicaliser.name_quality_score('Qantas Airways')
    score_short = TestCanonicaliser.name_quality_score('Qantas')

    assert_operator score_long, :>, score_short
  end

  # ==========================================================================
  # Tests for best_name_from
  # ==========================================================================

  test 'best_name_from returns nil for blank input' do
    assert_nil TestCanonicaliser.best_name_from(nil)
    assert_nil TestCanonicaliser.best_name_from([])
  end

  test 'best_name_from picks name with codes over name without' do
    candidates = [
      { name: 'QANTAS PTY LTD', has_icao: false, has_iata: false },
      { name: 'Qantas Airways', has_icao: true, has_iata: true }
    ]

    assert_equal 'Qantas Airways', TestCanonicaliser.best_name_from(candidates)
  end

  test 'best_name_from picks proper case over ALL CAPS' do
    candidates = [
      { name: 'VIRGIN AUSTRALIA', has_icao: false, has_iata: false },
      { name: 'Virgin Australia', has_icao: false, has_iata: false }
    ]

    assert_equal 'Virgin Australia', TestCanonicaliser.best_name_from(candidates)
  end

  # ==========================================================================
  # Tests for different_operators?
  # ==========================================================================

  test 'different_operators returns false for blank input' do
    assert_not TestCanonicaliser.different_operators?(nil, { name: 'Test' })
    assert_not TestCanonicaliser.different_operators?({ name: 'Test' }, nil)
  end

  test 'different_operators returns true when ICAO codes differ' do
    op1 = { name: 'Air Express', icao_code: 'AEJ', iata_code: nil }
    op2 = { name: 'Air Express', icao_code: 'AEQ', iata_code: nil }

    assert TestCanonicaliser.different_operators?(op1, op2)
  end

  test 'different_operators returns true when IATA codes differ' do
    op1 = { name: 'Test Air', icao_code: nil, iata_code: 'TA' }
    op2 = { name: 'Test Air', icao_code: nil, iata_code: 'TB' }

    assert TestCanonicaliser.different_operators?(op1, op2)
  end

  test 'different_operators returns false when ICAO codes match' do
    op1 = { name: 'Qantas', icao_code: 'QFA', iata_code: 'QF' }
    op2 = { name: 'Qantas Airways Ltd', icao_code: 'QFA', iata_code: 'QF' }

    assert_not TestCanonicaliser.different_operators?(op1, op2)
  end

  test 'different_operators returns false when one has codes and other does not' do
    op1 = { name: 'Qantas', icao_code: 'QFA', iata_code: 'QF' }
    op2 = { name: 'Qantas Airways Ltd', icao_code: nil, iata_code: nil }

    assert_not TestCanonicaliser.different_operators?(op1, op2)
  end

  # ==========================================================================
  # Tests for normalise_for_display
  # ==========================================================================

  test 'normalise_for_display converts ALL CAPS to title case' do
    assert_equal 'Qantas Airways', TestCanonicaliser.normalise_for_display('QANTAS AIRWAYS')
  end

  test 'normalise_for_display normalises corporate suffix casing' do
    assert_match(/Pty Ltd/, TestCanonicaliser.normalise_for_display('Test PTY LTD'))
    assert_match(/GmbH/, TestCanonicaliser.normalise_for_display('Test GMBH'))
    assert_match(/LLC/, TestCanonicaliser.normalise_for_display('Test llc'))
  end

  # ==========================================================================
  # Regression tests
  # ==========================================================================

  test 'regression: Sunstate Airlines duplicates should have same key' do
    # These are exact duplicates that should merge
    key1 = TestCanonicaliser.canonical_name_key('Sunstate Airlines (Qld)')
    key2 = TestCanonicaliser.canonical_name_key('Sunstate Airlines (Qld)')

    assert_equal key1, key2
  end

  test 'regression: Nas Air vs Nasair should have same key' do
    key1 = TestCanonicaliser.canonical_name_key('Nas Air')
    key2 = TestCanonicaliser.canonical_name_key('Nasair')

    assert_equal key1, key2
  end

  test 'regression: Air Express with different ICAO codes are different operators' do
    op1 = { name: 'Air Express', icao_code: 'AEJ', iata_code: nil }  # Tanzania
    op2 = { name: 'Air Express', icao_code: 'AEQ', iata_code: nil }  # Sweden

    assert TestCanonicaliser.different_operators?(op1, op2)
  end
end