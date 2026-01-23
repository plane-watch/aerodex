# frozen_string_literal: true

# Shared normalisation rules for manufacturer names across processors.
#
# == Purpose
#
# Different data sources use different names for the same manufacturer:
# - ICAO uses legal names: "GIE Airbus Industrie (France/Germany/UK/Spain)"
# - CASA uses common names: "AIRBUS"
# - VRS uses mixed formats: "Airbus Industrie"
#
# This concern normalises all variations to a single canonical form for
# consistent matching and display.
#
# == Normalisation Strategy
#
# 1. **Pattern Matching**: Known manufacturer name variations are mapped to
#    canonical names using regex patterns. First match wins.
#
# 2. **Corporate Suffix Removal**: Legal suffixes like "Ltd", "GmbH", "SAS"
#    are stripped as they vary by jurisdiction and time (via BusinessNameNormalisation).
#
# 3. **Country Annotation Removal**: Country identifiers like "(France)" are
#    extracted separately and removed from the name.
#
# 4. **Case Normalisation**: ALL CAPS names are titleized for readability,
#    except short acronyms (≤4 chars) which are preserved.
#
# == Usage
#
# Include in class methods:
#   class MyProcessor < Processors::Base
#     extend ManufacturerNormalisation
#   end
#
# Include in instance methods:
#   class MyModel < ApplicationRecord
#     include ManufacturerNormalisation
#   end
#
# == Adding New Patterns
#
# When adding patterns to MANUFACTURER_NAME_PATTERNS:
# - More specific patterns should come before general ones
# - Use case-insensitive matching (/i flag)
# - End patterns with $ or .* to match full strings
# - Test against real data from all sources
#
# @see Processors::Manufacturer::CfappsICAOInt Uses this for ICAO imports
# @see Processors::Aircraft::Base Uses this for aircraft registration matching
# @see BusinessNameNormalisation Base concern for corporate suffix stripping
module ManufacturerNormalisation
  extend ActiveSupport::Concern
  include BusinessNameNormalisation

  # When this module is extended (for class methods), also extend the dependency.
  # The `include BusinessNameNormalisation` above only works when this module is
  # included (for instance methods). For extend, we need to explicitly extend the
  # dependency so its methods become class methods on the extending class.
  def self.extended(base)
    base.extend(BusinessNameNormalisation)
  end

  # Patterns for normalising manufacturer names to canonical forms.
  # Each entry is [pattern, replacement].
  # Order matters - first match wins.
  MANUFACTURER_NAME_PATTERNS = [
    # Major manufacturers with many variations
    [/The Boeing Company/i, 'Boeing'],
    [/Boeing Commercial Airplanes/i, 'Boeing'],
    [/Boeing Aircraft/i, 'Boeing'],
    [/GIE Airbus Industrie/i, 'Airbus'],
    [/Airbus Industrie/i, 'Airbus'],
    [/Airbus SAS/i, 'Airbus'],
    [/Airbus S\.?A\.?S\.?/i, 'Airbus'],
    [/Airbus Helicopters.*$/i, 'Airbus Helicopters'],
    [/Airbus Defence and Space.*$/i, 'Airbus Defence and Space'],
    [/Airbus Military.*$/i, 'Airbus Military'],

    # Cessna/Textron
    [/Cessna Aircraft Company/i, 'Cessna'],
    [/Cessna Aircraft/i, 'Cessna'],
    [/Textron Aviation.*$/i, 'Textron Aviation'],

    # Piper
    [/Piper Aircraft.*$/i, 'Piper'],
    [/The New Piper.*$/i, 'Piper'],

    # Beechcraft/Hawker
    [/Beech Aircraft.*$/i, 'Beechcraft'],
    [/Beechcraft.*$/i, 'Beechcraft'],
    [/Hawker Beechcraft.*$/i, 'Hawker Beechcraft'],
    [/Raytheon Aircraft.*$/i, 'Raytheon'],

    # Russian/Soviet manufacturers
    [/Antonov.*$/i, 'Antonov'],
    [/Aviatsionny.*Tupoleva/i, 'Tupolev'],
    [/Tupolev.*$/i, 'Tupolev'],
    [/Aviatsionnyi Kompleks.*Ilyushina/i, 'Ilyushin'],
    [/Ilyushin.*$/i, 'Ilyushin'],
    [/Voyenno-Promyshlennyi Komplex Sukhoi/i, 'Sukhoi'],
    [/Sukhoi.*$/i, 'Sukhoi'],
    [/Aviatsionnyi Nauchno-Promyshlennyi Kompleks MiG/i, 'MiG'],
    [/Mikoyan.*$/i, 'MiG'],
    [/Moskovskii.*Yakovleva/i, 'Yakovlev'],
    [/Yakovlev.*$/i, 'Yakovlev'],
    [/Mil OKB/i, 'Mil'],
    [/Kamov.*$/i, 'Kamov'],
    [/Beriev.*$/i, 'Beriev'],

    # European manufacturers
    [/Societe Nationale Industrielle Aerospatiale/i, 'Aerospatiale'],
    [/Aerospatiale Matra/i, 'Aerospatiale'],
    [/Aerospatiale.*$/i, 'Aerospatiale'],
    [/Eurocopter.*$/i, 'Eurocopter'],
    [/Pilatus Aircraft Ltd.*/i, 'Pilatus'],
    [/Pilatus Aircraft/i, 'Pilatus'],
    [/Pilatus Flugzeugwerke/i, 'Pilatus'],
    [/Fokker.*$/i, 'Fokker'],
    [/Atr - Gie Avions.*$/i, 'ATR'],
    [/ATR.*GIE/i, 'ATR'],
    [/GIE Avions de Transport/i, 'ATR'],
    [/Saab AB/i, 'SAAB'],
    [/S\.?A\.?A\.?B\.?.*$/i, 'SAAB'],
    [/Dornier Luftfahrt/i, 'Dornier'],
    [/Dornier-Werke/i, 'Dornier'],
    [/Dornier.*$/i, 'Dornier'],
    [/S\.?O\.?C\.?A\.?T\.?A\.?.*$/i, 'SOCATA'],
    [/Daher-Socata/i, 'SOCATA'],
    [/Dassault.*$/i, 'Dassault'],
    [/British Aerospace.*$/i, 'British Aerospace'],
    [/British Aircraft Corporation/i, 'BAC'],
    [/BAE Systems.*$/i, 'BAE Systems'],
    [/Construcciones Aeron[aá]uticas SA/i, 'CASA'],

    # British manufacturers
    [/The De Havilland Aircraft/i, 'de Havilland'],
    [/Hawker De Havilland/i, 'de Havilland'],
    [/de Havilland.*$/i, 'de Havilland'],
    [/Short Brothers.*$/i, 'Short Brothers'],
    [/Handley Page.*$/i, 'Handley Page'],
    [/A\.?V\.?\s*Roe.*$/i, 'Avro'],
    [/Hawker Aircraft/i, 'Hawker'],
    [/Hawker Siddeley.*$/i, 'Hawker Siddeley'],
    [/GKN Westland.*$/i, 'Westland'],

    # Italian manufacturers (AgustaWestland before Westland to avoid false matches)
    [/Agustawestland.*$/i, 'AgustaWestland'],
    [/Westland.*$/i, 'Westland'],
    [/Costruzioni Aeronautiche Tecnam.*$/i, 'Tecnam'],
    [/Tecnam.*$/i, 'Tecnam'],
    [/Partenavia Costruzioni Aeronautiche.*$/i, 'Partenavia'],
    [/Costruzioni Aeronautiche Giovanni Agusta/i, 'Agusta'],
    [/Agusta Aerospace.*$/i, 'Agusta'],
    [/Agusta S\.?p\.?A\.?/i, 'Agusta'],
    [/Leonardo S\.?P\.?A\.?.*$/i, 'Leonardo'],
    [/Finmeccanica S\.?P\.?A\.?.*$/i, 'Leonardo'],
    [/Aeronautica Macchi/i, 'Aermacchi'],
    [/Aermacchi.*$/i, 'Aermacchi'],
    [/Alenia Aermacchi/i, 'Alenia'],
    [/Alenia.*$/i, 'Alenia'],

    # American manufacturers
    [/North American Aviation/i, 'North American'],
    [/North American Rockwell/i, 'North American'],
    [/Robinson Helicopter Co/i, 'Robinson'],
    [/Robinson Helicopter/i, 'Robinson'],
    [/Embraer.*$/i, 'Embraer'],
    [/Empresa Brasileira de Aeron[aá]utica/i, 'Embraer'],
    [/Empresa Brasileira de AeronÃ¡utica/i, 'Embraer'],  # Handles mojibake encoding
    [/Mooney Aircraft Corp/i, 'Mooney'],
    [/Mooney Aircraft/i, 'Mooney'],
    [/American Champion.*$/i, 'American Champion'],
    [/Cirrus Design Corporation.*$/i, 'Cirrus'],
    [/Cirrus Aircraft/i, 'Cirrus'],
    [/McDonnell Douglas.*$/i, 'McDonnell Douglas'],
    [/McDonnell Aircraft/i, 'McDonnell Douglas'],
    [/Douglas Aircraft/i, 'Douglas'],
    [/Lockheed Martin.*$/i, 'Lockheed Martin'],
    [/Lockheed Aircraft/i, 'Lockheed'],
    [/Sikorsky Aircraft.*$/i, 'Sikorsky'],
    [/Vought-Sikorsky/i, 'Sikorsky'],
    [/Fairchild.*$/i, 'Fairchild'],
    [/General Dynamics.*$/i, 'General Dynamics'],
    [/Grumman American/i, 'Grumman'],
    [/Grumman Aircraft/i, 'Grumman'],
    [/Northrop Grumman.*$/i, 'Northrop Grumman'],
    [/Northrop Aircraft/i, 'Northrop'],
    [/Chance Vought/i, 'Vought'],
    [/Ling-Temco-Vought/i, 'Vought'],
    [/Vought Aircraft/i, 'Vought'],
    [/Hughes Helicopters/i, 'Hughes'],
    [/Consolidated-Vultee/i, 'Convair'],
    [/Consolidated Aircraft/i, 'Consolidated'],
    [/Curtiss-Wright.*$/i, 'Curtiss-Wright'],
    [/Republic Aviation/i, 'Republic'],
    [/Kaman Aerospace/i, 'Kaman'],

    # Helicopters
    [/Bell Helicopter Textron.*$/i, 'Bell'],
    [/Bell Helicopter Co/i, 'Bell'],
    [/Bell Textron.*$/i, 'Bell'],
    [/Bell Aircraft/i, 'Bell'],
    [/Hiller Aircraft/i, 'Hiller'],
    [/Enstrom Helicopter/i, 'Enstrom'],
    [/R\.?J\.?\s*Enstrom/i, 'Enstrom'],

    # Other
    [/Diamond Aircraft.*$/i, 'Diamond'],
    [/GippsAero Pty Ltd/i, 'GippsAero'],
    [/Gippsland Aeronautics Pty Ltd/i, 'GippsAero'],
    [/Commonwealth Aircraft Corporation.*$/i, 'CAC'],
    [/Bombardier Aerospace.*$/i, 'Bombardier'],
    [/Bombardier.*$/i, 'Bombardier'],
    [/Messerschmitt-B[oö]lkow-Blohm/i, 'MBB'],
    [/Messerschmitt AG/i, 'Messerschmitt'],
    [/Junkers Flugzeug/i, 'Junkers'],
    [/Heinkel.*$/i, 'Heinkel'],
    [/Focke-Wulf.*$/i, 'Focke-Wulf'],
    [/Hindustan Aeronautics/i, 'HAL'],
    [/Israel Aerospace Industries/i, 'IAI'],
    [/Korea Aerospace Industries/i, 'KAI'],
    [/Mitsubishi Aircraft/i, 'Mitsubishi'],
    [/Mitsubishi Heavy Industries/i, 'Mitsubishi'],
    [/Kawasaki Heavy Industries/i, 'Kawasaki'],
    [/Fuji Heavy Industries/i, 'Fuji'],
    [/PT Dirgantara Indonesia/i, 'Indonesian Aerospace'],
    [/PT Industri Pesawat Terbang/i, 'Indonesian Aerospace'],
  ].freeze

  # Normalises a manufacturer name to its canonical form.
  #
  # @param name [String] The manufacturer name to normalise
  # @return [String] The normalised name
  #
  # @example
  #   normalise_manufacturer_name("The Boeing Company")
  #   # => "Boeing"
  #
  #   normalise_manufacturer_name("GIE Airbus Industrie")
  #   # => "Airbus"
  def normalise_manufacturer_name(name)
    return nil if name.blank?

    result = name.to_s.strip

    # Apply known name mappings (first match wins)
    MANUFACTURER_NAME_PATTERNS.each do |pattern, replacement|
      if result.match?(pattern)
        result = replacement
        break
      end
    end

    # Remove corporate suffixes (from BusinessNameNormalisation)
    result = strip_corporate_suffixes(result)

    # Titleize if all caps (but not short acronyms)
    result = normalise_case(result)

    result
  end

  # Removes country annotation from a name (e.g., "(France)" or "(France/Germany)")
  #
  # @param name [String] The name with possible country annotation
  # @return [String] The name without country annotation
  def remove_country_annotation(name)
    return nil if name.blank?

    name.to_s.gsub(/\s*\([^)]*\)\s*$/, '').strip
  end

  # Extracts country from parentheses at end of name.
  # For multi-country entries, returns the first country.
  #
  # @param name [String] The name with country annotation
  # @return [String, nil] The extracted country or nil
  def extract_country_from_name(name)
    return nil if name.blank?
    return nil unless name =~ /\(([^)]+)\)\s*$/

    country = ::Regexp.last_match(1).strip
    # Handle multi-country entries like "France/Germany/UK/Spain"
    country.split('/').first&.strip
  end
end
