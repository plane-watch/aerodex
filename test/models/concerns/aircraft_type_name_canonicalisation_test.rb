# frozen_string_literal: true

require 'test_helper'

class AircraftTypeNameCanonicalisationTest < ActiveSupport::TestCase
  # Create a test class that extends the concern for testing
  class TestCanonicaliser
    extend AircraftTypeNameCanonicalisation
  end

  # ==========================================================================
  # Tests for canonical_name_key
  # ==========================================================================

  test 'canonical_name_key returns empty string for blank input' do
    assert_equal '', TestCanonicaliser.canonical_name_key(nil)
    assert_equal '', TestCanonicaliser.canonical_name_key('')
    assert_equal '', TestCanonicaliser.canonical_name_key('   ')
  end

  test 'canonical_name_key strips manufacturer prefixes' do
    # Same canonical key regardless of manufacturer prefix
    assert_equal 'an148', TestCanonicaliser.canonical_name_key('An-148')
    assert_equal 'an148', TestCanonicaliser.canonical_name_key('Antonov An-148')
  end

  test 'canonical_name_key strips various manufacturer prefixes' do
    assert_equal '737800', TestCanonicaliser.canonical_name_key('Boeing 737-800')
    assert_equal 'a320200', TestCanonicaliser.canonical_name_key('Airbus A320-200')
    assert_equal 'erj145', TestCanonicaliser.canonical_name_key('Embraer ERJ-145')
    assert_equal 'crj200', TestCanonicaliser.canonical_name_key('Bombardier CRJ-200')
    assert_equal '172', TestCanonicaliser.canonical_name_key('Cessna 172')
    assert_equal 'pc12', TestCanonicaliser.canonical_name_key('Pilatus PC-12')
  end

  test 'canonical_name_key strips designation prefixes' do
    # Military designation prefixes should be stripped
    assert_equal 'skyraider', TestCanonicaliser.canonical_name_key('A-1 Skyraider')
    assert_equal 'skyraider', TestCanonicaliser.canonical_name_key('Skyraider')
  end

  test 'canonical_name_key normalises hyphens and spaces' do
    # Same canonical key regardless of hyphen/space variations
    assert_equal 'a319neo', TestCanonicaliser.canonical_name_key('A-319neo')
    assert_equal 'a319neo', TestCanonicaliser.canonical_name_key('A319neo')
    assert_equal 'a319neo', TestCanonicaliser.canonical_name_key('A 319 neo')
  end

  test 'canonical_name_key is case insensitive' do
    assert_equal 'an148', TestCanonicaliser.canonical_name_key('AN-148')
    assert_equal 'an148', TestCanonicaliser.canonical_name_key('an-148')
    assert_equal 'an148', TestCanonicaliser.canonical_name_key('An-148')
  end

  test 'canonical_name_key removes non-alphanumeric characters' do
    assert_equal 'superag', TestCanonicaliser.canonical_name_key('Super Ag!')
    assert_equal 'test123', TestCanonicaliser.canonical_name_key('Test@123#')
  end

  # ==========================================================================
  # Tests for name_quality_score
  # ==========================================================================

  test 'name_quality_score returns 0 for blank input' do
    assert_equal 0, TestCanonicaliser.name_quality_score(nil)
    assert_equal 0, TestCanonicaliser.name_quality_score('')
    assert_equal 0, TestCanonicaliser.name_quality_score('   ')
  end

  test 'name_quality_score prefers names with manufacturer prefix' do
    # Names with manufacturer prefix score higher
    assert_operator TestCanonicaliser.name_quality_score('Antonov An-148'),
                    :>, TestCanonicaliser.name_quality_score('An-148')
    assert_operator TestCanonicaliser.name_quality_score('Boeing 737-800'),
                    :>, TestCanonicaliser.name_quality_score('737-800')
  end

  test 'name_quality_score prefers names with model designation' do
    # Names with designation pattern (letter-digits) score higher
    assert_operator TestCanonicaliser.name_quality_score('An-148'),
                    :>, TestCanonicaliser.name_quality_score('Mriya')
  end

  test 'name_quality_score penalises short nickname-only names' do
    # Short names without numbers are penalised
    score = TestCanonicaliser.name_quality_score('Jumbo')
    assert_operator score, :<, TestCanonicaliser.name_quality_score('Boeing 747-400')
  end

  test 'name_quality_score prefers longer descriptive names' do
    # Longer names generally score higher (up to a point)
    assert_operator TestCanonicaliser.name_quality_score('Boeing 737-800 Winglets'),
                    :>, TestCanonicaliser.name_quality_score('Boeing 737-800')
  end

  # ==========================================================================
  # Tests for best_name_from
  # ==========================================================================

  test 'best_name_from returns nil for blank input' do
    assert_nil TestCanonicaliser.best_name_from(nil)
    assert_nil TestCanonicaliser.best_name_from([])
  end

  test 'best_name_from picks name with manufacturer prefix' do
    names = ['An-148', 'Antonov An-148']
    assert_equal 'Antonov An-148', TestCanonicaliser.best_name_from(names)
  end

  test 'best_name_from picks name with designation over nickname' do
    names = ['Skyraider', 'A-1 Skyraider']
    assert_equal 'A-1 Skyraider', TestCanonicaliser.best_name_from(names)
  end

  test 'best_name_from handles mixed quality names' do
    names = ['328JET', 'Dornier 328JET', '328 Jet']
    assert_equal 'Dornier 328JET', TestCanonicaliser.best_name_from(names)
  end

  test 'best_name_from ignores nil values in array' do
    names = [nil, 'An-148', nil, 'Antonov An-148', nil]
    assert_equal 'Antonov An-148', TestCanonicaliser.best_name_from(names)
  end

  # ==========================================================================
  # Tests for different_variants? - cases that should return FALSE (same variant)
  # ==========================================================================

  test 'different_variants returns false for blank input' do
    assert_not TestCanonicaliser.different_variants?(nil, 'An-148')
    assert_not TestCanonicaliser.different_variants?('An-148', nil)
    assert_not TestCanonicaliser.different_variants?('', 'An-148')
    assert_not TestCanonicaliser.different_variants?('An-148', '')
  end

  test 'different_variants returns false for same name with manufacturer prefix' do
    # These are the same aircraft, just different naming conventions
    assert_not TestCanonicaliser.different_variants?('An-148', 'Antonov An-148')
    assert_not TestCanonicaliser.different_variants?('737-800', 'Boeing 737-800')
    assert_not TestCanonicaliser.different_variants?('A320-200', 'Airbus A320-200')
  end

  test 'different_variants returns false for lazy input without designation' do
    # "Gazelle" is just a lazy way of writing "SA-341 Gazelle"
    assert_not TestCanonicaliser.different_variants?('SA-341 Gazelle', 'Gazelle')
    assert_not TestCanonicaliser.different_variants?('A-9 Quail', 'Quail')
    assert_not TestCanonicaliser.different_variants?('L-39 Albatros', 'Albatros')
  end

  test 'different_variants returns false for hyphen variations' do
    # Same aircraft, different hyphenation
    assert_not TestCanonicaliser.different_variants?('A319neo', 'A-319neo')
    assert_not TestCanonicaliser.different_variants?('328JET', 'Dornier 328JET')
  end

  # ==========================================================================
  # Tests for different_variants? - cases that should return TRUE (different variant)
  # ==========================================================================

  test 'different_variants returns true for different Boeing series' do
    # Different series numbers = different variants
    assert TestCanonicaliser.different_variants?('737-700', '737-800')
    assert TestCanonicaliser.different_variants?('747-400', '747-8')
    assert TestCanonicaliser.different_variants?('777-200', '777-300')
  end

  test 'different_variants returns true for different Airbus series' do
    assert TestCanonicaliser.different_variants?('A320-100', 'A320-200')
    assert TestCanonicaliser.different_variants?('A350-900', 'A350-1000')
    assert TestCanonicaliser.different_variants?('A380-800', 'A380-900')
  end

  test 'different_variants returns true for different military designations' do
    # SA-341 and SA-342 are different Gazelle variants
    assert TestCanonicaliser.different_variants?('SA-341 Gazelle', 'SA-342 Gazelle')
    # L-39 and L-139 are different
    assert TestCanonicaliser.different_variants?('L-39 Albatros', 'L-139 Albatros')
    # Different Orion variants
    assert TestCanonicaliser.different_variants?('G-801 Orion', 'G-802 Orion')
  end

  test 'different_variants returns true for executive vs commercial' do
    # BBJ is a business jet variant of 737
    assert TestCanonicaliser.different_variants?('737-800', '737-800 BBJ')
    assert TestCanonicaliser.different_variants?('737-800', 'Boeing BBJ2')
    # ACJ is Airbus corporate jet
    assert TestCanonicaliser.different_variants?('A320-200', 'ACJ320')
  end

  test 'different_variants returns true for cargo variants' do
    # Freighter variants are different
    assert TestCanonicaliser.different_variants?('737-800', '737-800 Freighter')
    assert TestCanonicaliser.different_variants?('747-400', '747-400 Cargo')
    assert TestCanonicaliser.different_variants?('777-200', '777-200 BCF')
  end

  test 'different_variants returns true for range variants' do
    # ER (Extended Range), LR (Long Range) are different
    assert TestCanonicaliser.different_variants?('777-200', '777-200ER')
    assert TestCanonicaliser.different_variants?('777-200', '777-200LR')
  end

  test 'different_variants returns true for generation variants' do
    # neo, MAX are new generation variants
    assert TestCanonicaliser.different_variants?('A320-200', 'A320neo')
    assert TestCanonicaliser.different_variants?('737-800', '737 MAX 8')
  end

  # ==========================================================================
  # Tests for extract_variant_number (private method tested via different_variants?)
  # ==========================================================================

  test 'different_variants correctly extracts Boeing-style variants' do
    # 737-XXX pattern
    assert TestCanonicaliser.different_variants?('737-700', '737-800')
    assert TestCanonicaliser.different_variants?('737-700', '737-900')
    assert_not TestCanonicaliser.different_variants?('737-800', '737-800')
  end

  test 'different_variants correctly extracts Airbus-style variants' do
    # AXXX-YYY pattern
    assert TestCanonicaliser.different_variants?('A320-100', 'A320-200')
    assert TestCanonicaliser.different_variants?('A350-900', 'A350-1000')
  end

  test 'different_variants correctly extracts military designation variants' do
    # XX-YYY pattern (SA-341, L-39, etc.)
    assert TestCanonicaliser.different_variants?('SA-341', 'SA-342')
    assert TestCanonicaliser.different_variants?('L-39', 'L-159')
    assert TestCanonicaliser.different_variants?('D-112', 'D-119')
  end

  # ==========================================================================
  # Integration tests
  # ==========================================================================

  test 'Processors::AircraftType::AircraftType extends AircraftTypeNameCanonicalisation' do
    assert Processors::AircraftType::AircraftType.respond_to?(:canonical_name_key)
    assert Processors::AircraftType::AircraftType.respond_to?(:name_quality_score)
    assert Processors::AircraftType::AircraftType.respond_to?(:best_name_from)
    assert Processors::AircraftType::AircraftType.respond_to?(:different_variants?)
  end

  # ==========================================================================
  # Regression tests - specific cases that were previously broken
  # ==========================================================================

  test 'regression: Gazelle variants are handled correctly' do
    # SA-341 and SA-342 are different variants (different engines)
    assert TestCanonicaliser.different_variants?('SA-341 Gazelle', 'SA-342 Gazelle')
    # But "Gazelle" alone should merge with either (it is just lazy input)
    assert_not TestCanonicaliser.different_variants?('SA-341 Gazelle', 'Gazelle')
    assert_not TestCanonicaliser.different_variants?('SA-342 Gazelle', 'Gazelle')
  end

  test 'regression: 737-700 and 737-800 are kept separate' do
    assert TestCanonicaliser.different_variants?('737-700', '737-800')
    assert TestCanonicaliser.different_variants?('Boeing 737-700', 'Boeing 737-800')
  end

  test 'regression: commercial vs BBJ variants are kept separate' do
    # Commercial 737-800 should not merge with BBJ
    assert TestCanonicaliser.different_variants?('737-800', '737-800 BBJ')
    assert TestCanonicaliser.different_variants?('Boeing 737-800', 'Boeing BBJ2')
  end

  test 'regression: manufacturer prefix does not affect merging' do
    # Same aircraft with/without manufacturer should merge
    assert_not TestCanonicaliser.different_variants?('737-800', 'Boeing 737-800')
    assert_not TestCanonicaliser.different_variants?('An-148', 'Antonov An-148')
    assert_not TestCanonicaliser.different_variants?('A320-200', 'Airbus A320-200')
  end

  test 'regression: designation prefix stripping works correctly' do
    # A-1 Skyraider and Skyraider should have same canonical key
    assert_equal TestCanonicaliser.canonical_name_key('A-1 Skyraider'),
                 TestCanonicaliser.canonical_name_key('Skyraider')
  end
end