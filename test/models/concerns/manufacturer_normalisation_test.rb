# frozen_string_literal: true

require 'test_helper'

class ManufacturerNormalisationTest < ActiveSupport::TestCase
  # Create a test class that extends the concern for testing
  class TestNormaliser
    extend ManufacturerNormalisation
  end

  # Tests for normalise_manufacturer_name

  test 'normalise_manufacturer_name returns nil for blank input' do
    assert_nil TestNormaliser.normalise_manufacturer_name(nil)
    assert_nil TestNormaliser.normalise_manufacturer_name('')
    assert_nil TestNormaliser.normalise_manufacturer_name('   ')
  end

  test 'normalise_manufacturer_name strips whitespace' do
    assert_equal 'Boeing', TestNormaliser.normalise_manufacturer_name('  Boeing  ')
  end

  test 'normalise_manufacturer_name applies pattern matching for Boeing' do
    assert_equal 'Boeing', TestNormaliser.normalise_manufacturer_name('The Boeing Company')
    assert_equal 'Boeing', TestNormaliser.normalise_manufacturer_name('Boeing Commercial Airplanes')
  end

  test 'normalise_manufacturer_name applies pattern matching for Airbus' do
    assert_equal 'Airbus', TestNormaliser.normalise_manufacturer_name('GIE Airbus Industrie')
    assert_equal 'Airbus', TestNormaliser.normalise_manufacturer_name('Airbus Industrie')
    assert_equal 'Airbus', TestNormaliser.normalise_manufacturer_name('Airbus SAS')
    assert_equal 'Airbus', TestNormaliser.normalise_manufacturer_name('Airbus S.A.S.')
  end

  test 'normalise_manufacturer_name applies pattern matching for Airbus subsidiaries' do
    assert_equal 'Airbus Helicopters', TestNormaliser.normalise_manufacturer_name('Airbus Helicopters Deutschland GmbH')
    assert_equal 'Airbus Defence and Space', TestNormaliser.normalise_manufacturer_name('Airbus Defence and Space Ltd')
  end

  test 'normalise_manufacturer_name applies pattern matching for Cessna' do
    assert_equal 'Cessna', TestNormaliser.normalise_manufacturer_name('Cessna Aircraft Company')
    assert_equal 'Cessna', TestNormaliser.normalise_manufacturer_name('Cessna Aircraft')
  end

  test 'normalise_manufacturer_name applies pattern matching for Piper' do
    assert_equal 'Piper', TestNormaliser.normalise_manufacturer_name('Piper Aircraft Corporation')
    assert_equal 'Piper', TestNormaliser.normalise_manufacturer_name('The New Piper Aircraft Inc')
  end

  test 'normalise_manufacturer_name applies pattern matching for Beechcraft' do
    assert_equal 'Beechcraft', TestNormaliser.normalise_manufacturer_name('Beech Aircraft Corporation')
    assert_equal 'Beechcraft', TestNormaliser.normalise_manufacturer_name('Beechcraft Corporation')
  end

  test 'normalise_manufacturer_name applies pattern matching for European manufacturers' do
    assert_equal 'Aerospatiale', TestNormaliser.normalise_manufacturer_name('Societe Nationale Industrielle Aerospatiale')
    assert_equal 'Pilatus', TestNormaliser.normalise_manufacturer_name('Pilatus Aircraft Ltd')
    assert_equal 'ATR', TestNormaliser.normalise_manufacturer_name('Atr - Gie Avions De Transport Regional')
    assert_equal 'SAAB', TestNormaliser.normalise_manufacturer_name('S.A.A.B.')
    assert_equal 'Dornier', TestNormaliser.normalise_manufacturer_name('Dornier Luftfahrt GmbH')
  end

  test 'normalise_manufacturer_name applies pattern matching for Italian manufacturers' do
    assert_equal 'Tecnam', TestNormaliser.normalise_manufacturer_name('Costruzioni Aeronautiche Tecnam S.r.l.')
    assert_equal 'Agusta', TestNormaliser.normalise_manufacturer_name('Costruzioni Aeronautiche Giovanni Agusta')
    assert_equal 'AgustaWestland', TestNormaliser.normalise_manufacturer_name('AgustaWestland S.p.A.')
    assert_equal 'Leonardo', TestNormaliser.normalise_manufacturer_name('Leonardo S.P.A. Helicopters')
  end

  test 'normalise_manufacturer_name applies pattern matching for American manufacturers' do
    assert_equal 'Robinson', TestNormaliser.normalise_manufacturer_name('Robinson Helicopter Co')
    assert_equal 'Embraer', TestNormaliser.normalise_manufacturer_name('Embraer S.A.')
    assert_equal 'Cirrus', TestNormaliser.normalise_manufacturer_name('Cirrus Design Corporation')
    assert_equal 'McDonnell Douglas', TestNormaliser.normalise_manufacturer_name('McDonnell Douglas Corporation')
  end

  test 'normalise_manufacturer_name applies pattern matching for helicopters' do
    assert_equal 'Bell', TestNormaliser.normalise_manufacturer_name('Bell Helicopter Textron Inc')
    assert_equal 'Bell', TestNormaliser.normalise_manufacturer_name('Bell Textron Inc')
    assert_equal 'Eurocopter', TestNormaliser.normalise_manufacturer_name('Eurocopter Deutschland GmbH')
  end

  test 'normalise_manufacturer_name applies pattern matching for Russian manufacturers' do
    assert_equal 'Antonov', TestNormaliser.normalise_manufacturer_name('Antonov OKB')
    assert_equal 'Tupolev', TestNormaliser.normalise_manufacturer_name('Aviatsionny Nauchno-Tekhnishesky Kompleks Imeni A N Tupoleva OAO')
    assert_equal 'Ilyushin', TestNormaliser.normalise_manufacturer_name('Aviatsionnyi Kompleks Imeni S.V.Ilyushina OAO')
    assert_equal 'Sukhoi', TestNormaliser.normalise_manufacturer_name('Gosudarstvennoye Unitarnoye Predpriyatie Aviatsionnyi Voyenno-Promyshlennyi Komplex Sukhoi')
    assert_equal 'MiG', TestNormaliser.normalise_manufacturer_name('Aviatsionnyi Nauchno-Promyshlennyi Kompleks MiG')
    assert_equal 'Yakovlev', TestNormaliser.normalise_manufacturer_name('Moskovskii Mashinostroitelnyy Zavod "Skorost" Imeni A.S.Yakovleva')
    assert_equal 'Mil', TestNormaliser.normalise_manufacturer_name('Mil OKB')
    assert_equal 'Kamov', TestNormaliser.normalise_manufacturer_name('Kamov OAO')
    assert_equal 'Beriev', TestNormaliser.normalise_manufacturer_name('Beriev OKB')
  end

  test 'normalise_manufacturer_name applies pattern matching for British manufacturers' do
    assert_equal 'de Havilland', TestNormaliser.normalise_manufacturer_name('The De Havilland Aircraft Company Ltd')
    assert_equal 'Short Brothers', TestNormaliser.normalise_manufacturer_name('Short Brothers & Harland Ltd')
    assert_equal 'Avro', TestNormaliser.normalise_manufacturer_name('A.V.Roe & Company')
    assert_equal 'Westland', TestNormaliser.normalise_manufacturer_name('GKN Westland Helicopters Ltd')
    assert_equal 'BAC', TestNormaliser.normalise_manufacturer_name('British Aircraft Corporation Ltd')
  end

  test 'normalise_manufacturer_name applies pattern matching for other major manufacturers' do
    assert_equal 'Douglas', TestNormaliser.normalise_manufacturer_name('Douglas Aircraft Company Inc')
    assert_equal 'Grumman', TestNormaliser.normalise_manufacturer_name('Grumman Aircraft Engineering Corporation')
    assert_equal 'Northrop Grumman', TestNormaliser.normalise_manufacturer_name('Northrop Grumman Corporation')
    assert_equal 'General Dynamics', TestNormaliser.normalise_manufacturer_name('General Dynamics Corporation')
    assert_equal 'Vought', TestNormaliser.normalise_manufacturer_name('Chance Vought Aircraft Inc')
    assert_equal 'CASA', TestNormaliser.normalise_manufacturer_name('Construcciones Aeronáuticas SA')
  end

  test 'normalise_manufacturer_name removes corporate suffixes' do
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Ltd')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Ltd.')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation GmbH')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Inc')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Inc.')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation S.A.')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Pty Ltd')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation Corporation')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation A/S')
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('Acme Aviation AB')
  end

  test 'normalise_manufacturer_name removes Eastern European corporate suffixes' do
    assert_equal 'Aero Vodochody', TestNormaliser.normalise_manufacturer_name('Aero Vodochody AS')
    assert_equal 'Aeropro', TestNormaliser.normalise_manufacturer_name('Aeropro sro')
    assert_equal 'Aerospool', TestNormaliser.normalise_manufacturer_name('Aerospool spol sro')
    assert_equal 'Pipistrel', TestNormaliser.normalise_manufacturer_name('Pipistrel doo')
    assert_equal 'Corvus Aircraft', TestNormaliser.normalise_manufacturer_name('Corvus Aircraft Kft')
  end

  test 'normalise_manufacturer_name removes Germanic corporate suffixes' do
    assert_equal 'Airconcept Flugzeug und Gerätebau', TestNormaliser.normalise_manufacturer_name('Airconcept Flugzeug und Gerätebau GmbH & Co KG')
    assert_equal 'Akademische Fliegergruppe Berlin', TestNormaliser.normalise_manufacturer_name('Akademische Fliegergruppe Berlin eV')
    assert_equal 'Binder Aviatik', TestNormaliser.normalise_manufacturer_name('Binder Aviatik KG')
  end

  test 'normalise_manufacturer_name removes other international corporate suffixes' do
    assert_equal 'Eiriavion', TestNormaliser.normalise_manufacturer_name('Eiriavion OY')
    assert_equal 'Composites Technology Research Malaysia', TestNormaliser.normalise_manufacturer_name('Composites Technology Research Malaysia Sdn Bhd')
    assert_equal 'Lambert Aircraft Engineering', TestNormaliser.normalise_manufacturer_name('Lambert Aircraft Engineering bvba')
    assert_equal 'Jonker Sailplanes', TestNormaliser.normalise_manufacturer_name('Jonker Sailplanes CC')
  end

  test 'normalise_manufacturer_name titleizes all-caps names longer than 4 characters' do
    assert_equal 'Acme Aviation', TestNormaliser.normalise_manufacturer_name('ACME AVIATION')
  end

  test 'normalise_manufacturer_name preserves short acronyms' do
    assert_equal 'ATR', TestNormaliser.normalise_manufacturer_name('ATR')
    assert_equal 'MBB', TestNormaliser.normalise_manufacturer_name('MBB')
  end

  test 'normalise_manufacturer_name is case insensitive for pattern matching' do
    assert_equal 'Boeing', TestNormaliser.normalise_manufacturer_name('THE BOEING COMPANY')
    assert_equal 'Airbus', TestNormaliser.normalise_manufacturer_name('gie airbus industrie')
  end

  # Tests for remove_country_annotation

  test 'remove_country_annotation returns nil for blank input' do
    assert_nil TestNormaliser.remove_country_annotation(nil)
    assert_nil TestNormaliser.remove_country_annotation('')
  end

  test 'remove_country_annotation removes parenthetical country at end' do
    assert_equal 'Boeing', TestNormaliser.remove_country_annotation('Boeing (USA)')
    assert_equal 'Airbus', TestNormaliser.remove_country_annotation('Airbus (France)')
  end

  test 'remove_country_annotation removes multi-country annotation' do
    assert_equal 'GIE Airbus Industrie', TestNormaliser.remove_country_annotation('GIE Airbus Industrie (France/Germany/UK/Spain)')
  end

  test 'remove_country_annotation preserves names without annotations' do
    assert_equal 'Boeing', TestNormaliser.remove_country_annotation('Boeing')
  end

  test 'remove_country_annotation strips surrounding whitespace' do
    assert_equal 'Boeing', TestNormaliser.remove_country_annotation('  Boeing (USA)  ')
  end

  # Tests for extract_country_from_name

  test 'extract_country_from_name returns nil for blank input' do
    assert_nil TestNormaliser.extract_country_from_name(nil)
    assert_nil TestNormaliser.extract_country_from_name('')
  end

  test 'extract_country_from_name returns nil when no country annotation present' do
    assert_nil TestNormaliser.extract_country_from_name('Boeing')
    assert_nil TestNormaliser.extract_country_from_name('Airbus Industrie')
  end

  test 'extract_country_from_name extracts single country' do
    assert_equal 'USA', TestNormaliser.extract_country_from_name('Boeing (USA)')
    assert_equal 'France', TestNormaliser.extract_country_from_name('Airbus (France)')
  end

  test 'extract_country_from_name extracts first country from multi-country' do
    assert_equal 'France', TestNormaliser.extract_country_from_name('GIE Airbus Industrie (France/Germany/UK/Spain)')
  end

  test 'extract_country_from_name strips whitespace from extracted country' do
    assert_equal 'USA', TestNormaliser.extract_country_from_name('Boeing ( USA )')
  end

  # Integration tests for the concern being used by processors

  test 'Processors::Aircraft::Base extends ManufacturerNormalisation' do
    assert Processors::Aircraft::Base.respond_to?(:normalise_manufacturer_name)
    assert Processors::Aircraft::Base.respond_to?(:remove_country_annotation)
    assert Processors::Aircraft::Base.respond_to?(:extract_country_from_name)
  end

  test 'Processors::Manufacturer::CfappsICAOInt extends ManufacturerNormalisation' do
    assert Processors::Manufacturer::CfappsICAOInt.respond_to?(:normalise_manufacturer_name)
    assert Processors::Manufacturer::CfappsICAOInt.respond_to?(:remove_country_annotation)
    assert Processors::Manufacturer::CfappsICAOInt.respond_to?(:extract_country_from_name)
  end
end