# frozen_string_literal: true

# Shared normalisation rules for business entity names.
#
# Provides common utilities for normalising corporate names by removing legal
# entity suffixes (Ltd, Inc, GmbH, etc.) and standardising case.
#
# This concern is intended to be extended by entity-specific normalisers
# like ManufacturerNormalisation while providing shared functionality.
#
# == Usage
#
# Include in class methods:
#   class MyProcessor < Processors::Base
#     extend BusinessNameNormalisation
#   end
#
# Include in instance methods:
#   class MyModel < ApplicationRecord
#     include BusinessNameNormalisation
#   end
#
# @see ManufacturerNormalisation Uses this for manufacturer name normalisation
module BusinessNameNormalisation
  extend ActiveSupport::Concern

  # Corporate suffixes to remove from business names.
  # Covers common legal entity types across jurisdictions:
  # - Germanic: GmbH, AG, KG, OHG, eV, eK, GmbH & Co KG
  # - Romance: SA, SAS, SL, SpA, Srl, SARL
  # - Anglo: Ltd, Inc, LLC, Corp, Pty Ltd, plc
  # - Nordic: AB, A/S, OY, AS
  # - Eastern European: sro, spol, doo, Kft, OAO, OOO, JSC
  # - Other: Sdn Bhd (Malaysia), CC (South Africa), bvba (Belgium)
  CORPORATE_SUFFIXES = /\s+(
    S\.?A\.?S\.?|
    S\.?A\.?R\.?L\.?|
    S\.?A\.?|
    Ltd\.?|
    Inc\.?|
    GmbH(?:\s*&\s*Co\.?\s*KG)?|
    S\.?p\.?A\.?|
    S\.?r\.?l\.?|
    GIE|
    S\.?L\.?|
    LLC|
    FZ-LLC|
    Co\.?|
    Corp\.?|
    Pty\.?\s*Ltd\.?|
    Pty\.?\s*Limited|
    Limited|
    Corporation|
    Company|
    N\.?V\.?|
    B\.?V\.?|
    A\.?G\.?|
    A\/S|
    AB|
    AS|
    OY|
    KG|
    OHG|
    eV|
    eK|
    sro|
    spol\.?\s*sro|
    spol|
    doo|
    DOO|
    Kft|
    OAO|
    OOO|
    JSC|
    plc|
    Sdn\.?\s*Bhd\.?|
    bvba|
    VOF|
    CC|
    Enr
  )\s*$/ix.freeze

  # Common airline/operator business terms that can be stripped for matching.
  # These are often included in the legal name but not the trading name.
  AIRLINE_BUSINESS_TERMS = /\s+(
    Airlines?|
    Airways|
    Aviation|
    Air\s*Lines?|
    Air\s*Transport|
    Air\s*Services?|
    Cargo|
    Express|
    Regional|
    International|
    Domestic|
    Operations?|
    Holdings?|
    Group
  )\s*$/ix.freeze

  # Strips corporate suffixes from a business name.
  #
  # @param name [String] The name to strip
  # @return [String, nil] The stripped name, or nil if input was blank
  #
  # @example
  #   strip_corporate_suffixes("Virgin Australia Pty Ltd")
  #   # => "Virgin Australia"
  #
  #   strip_corporate_suffixes("Airbus SAS")
  #   # => "Airbus"
  def strip_corporate_suffixes(name)
    return nil if name.blank?

    result = name.to_s.strip
    # Apply repeatedly in case of stacked suffixes like "Pty Ltd"
    loop do
      new_result = result.gsub(CORPORATE_SUFFIXES, '').strip
      break if new_result == result

      result = new_result
    end
    result
  end

  # Strips airline business terms from an operator name for matching.
  # Use this when trying to find fuzzy matches between operator names.
  #
  # @param name [String] The name to strip
  # @return [String, nil] The stripped name
  #
  # @example
  #   strip_airline_terms("Virgin Australia International Airlines")
  #   # => "Virgin Australia"
  def strip_airline_terms(name)
    return nil if name.blank?

    result = name.to_s.strip
    # Apply repeatedly to strip stacked terms
    loop do
      new_result = result.gsub(AIRLINE_BUSINESS_TERMS, '').strip
      break if new_result == result

      result = new_result
    end
    result
  end

  # Normalises a business name for matching purposes.
  # Strips corporate suffixes and normalises case.
  #
  # @param name [String] The name to normalise
  # @return [String, nil] The normalised name
  #
  # @example
  #   normalise_business_name("VIRGIN AUSTRALIA PTY LTD")
  #   # => "Virgin Australia"
  def normalise_business_name(name)
    return nil if name.blank?

    result = strip_corporate_suffixes(name)
    result = normalise_case(result)
    result
  end

  # Normalises a business name aggressively for operator matching.
  # Strips both corporate suffixes AND airline business terms.
  #
  # @param name [String] The name to normalise
  # @return [String, nil] The normalised name
  #
  # @example
  #   normalise_operator_name("VIRGIN AUSTRALIA INTERNATIONAL AIRLINES PTY LTD")
  #   # => "Virgin Australia"
  def normalise_operator_name(name)
    return nil if name.blank?

    result = strip_corporate_suffixes(name)
    result = strip_airline_terms(result)
    result = normalise_case(result)
    result
  end

  # Normalises case for display.
  # Titleizes ALL CAPS names, but preserves short acronyms.
  #
  # @param name [String] The name to normalise
  # @return [String] The case-normalised name
  #
  # @example
  #   normalise_case("VIRGIN AUSTRALIA")
  #   # => "Virgin Australia"
  #
  #   normalise_case("IATA")
  #   # => "IATA" (preserved - short acronym)
  def normalise_case(name)
    return nil if name.blank?

    result = name.to_s.strip
    # Titleize if all caps (but not short acronyms)
    result = result.titleize if result == result.upcase && result.length > 4
    result
  end

  # Creates a simplified key for fuzzy matching.
  # Removes all non-alphanumeric characters and lowercases.
  #
  # @param name [String] The name to simplify
  # @return [String, nil] The simplified key
  #
  # @example
  #   match_key("Virgin Australia Pty Ltd")
  #   # => "virginaustralia"
  def match_key(name)
    normalised = normalise_operator_name(name)
    return nil if normalised.blank?

    normalised.downcase.gsub(/[^a-z0-9]/, '')
  end
end