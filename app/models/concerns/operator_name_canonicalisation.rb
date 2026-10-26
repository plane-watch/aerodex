# frozen_string_literal: true

# Canonicalises operator names for deduplication.
#
# Different data sources use different naming conventions for the same operator:
# - "Qantas Airways Ltd" vs "Qantas Airways" (corporate suffix)
# - "Jet Kontor" vs "Jetkontor" (spacing variation)
# - "HELIWAY PTY LTD" vs "Heliway Pty Ltd" (casing)
#
# This concern provides methods to:
# 1. Generate a canonical key for grouping (merges duplicates)
# 2. Score names to pick the best/most descriptive one
# 3. Detect if two names represent genuinely different operators
#
# @example
#   canonical_name_key("Qantas Airways Ltd")  # => "qantasairways"
#   canonical_name_key("Qantas Airways")      # => "qantasairways"
#   # Both group together, we keep the one with ICAO/IATA codes
module OperatorNameCanonicalisation
  extend ActiveSupport::Concern

  # Corporate suffixes to strip for canonicalisation.
  # Ordered by specificity (longer patterns first) to avoid partial matches.
  # https://ithy.com/article/global-business-entity-abbreviation-guide-9xcy64o0
  CORPORATE_SUFFIXES = [
    # Australian/UK
    'pty ltd', 'pty. ltd.', 'pty. ltd', 'pty ltd.', 'proprietary limited',
    'limited', 'ltd.', 'ltd', 'plc', 'pty limited', 'pty. limited', 'proprietary ltd',
    # US
    'incorporated', 'inc.', 'inc',
    'l.l.c.', 'llc',
    'corporation', 'corp.', 'corp',
    'company', 'co.', 'co',
    # German
    'gmbh & co. kg', 'gmbh & co kg', 'gmbh',
    'ag',
    # French/Spanish/Italian
    's.a.r.l.', 'sarl', 's.a.s.', 'sas',
    's.p.a.', 'spa',
    's.a.', 'sa',
    's.l.', 'sl',
    # UK
    'plc',
    # Other
    'bv', 'b.v.', 'nv', 'n.v.', 'ab', 'as', 'oy', 'a/s', 'kk', 'k.k.', 'gk', 'g.k.',
    'pt', 'p.t.', 'bhd', 'b.h.d', 'pte ltd', 'ltda', 'srl', 's.r.l.', 'ibc',
  ].freeze

  # Pattern to match corporate suffixes at end of name (case-insensitive).
  # The word boundary ensures we don't match partial words.
  CORPORATE_SUFFIX_PATTERN = /\s*\b(#{CORPORATE_SUFFIXES.map { |s| Regexp.escape(s) }.join('|')})\s*\z/i

  # Generic terms that don't add uniqueness value - safe to strip for canonicalisation.
  # These terms are common across almost all operators and don't differentiate them.
  GENERIC_TERMS = %w[
    airlines airline airways airway aviation air aero aeronautics
    helicopters helicopter heli heliservices
    services service
    flying flight flights
    charter charters
    group holdings
  ].freeze

  # NOTE: The following terms MUST NOT be stripped as they indicate different operators:
  # - regional (e.g., "Virgin Australia Regional Airlines" ≠ "Virgin Australia")
  # - international (e.g., separate international subsidiary)
  # - domestic, national (indicates operational scope)
  # - cargo, freight (cargo operators have separate AOCs)
  # - express, link (regional/feeder services, e.g., "QantasLink")
  # - transport (may indicate different division)

  GENERIC_TERMS_PATTERN = /\b(#{GENERIC_TERMS.join('|')})\b/i

  # Legacy aliases for backwards compatibility (some code may reference COMMON_TERMS)
  COMMON_TERMS = GENERIC_TERMS
  COMMON_TERMS_PATTERN = GENERIC_TERMS_PATTERN

  # Generates a canonical key for grouping similar names.
  # Names that produce the same key will be considered duplicates.
  #
  # @param name [String] The operator name
  # @return [String] Normalised key for grouping
  #
  # @example
  #   canonical_name_key("Qantas Airways Ltd")  # => "qantasairways"
  #   canonical_name_key("Qantas Airways")      # => "qantasairways"
  #   canonical_name_key("Jet Kontor")          # => "jetkontor"
  #   canonical_name_key("Jetkontor")           # => "jetkontor"
  def canonical_name_key(name)
    return '' if name.blank?

    key = name.to_s.strip

    # Remove corporate suffixes
    key = key.sub(CORPORATE_SUFFIX_PATTERN, '')

    # Normalise to lowercase
    key = key.downcase

    # Remove all non-alphanumeric characters (spaces, hyphens, punctuation)
    key.gsub(/[^a-z0-9]/, '')
  end

  # Generates an aggressive canonical key that strips generic airline terms.
  # Use this for finding potential duplicates that differ by "Airlines" vs "Airways" etc.
  #
  # Note: Differentiating terms like "regional", "cargo", "international" are preserved
  # because they typically indicate separate operators with different AOCs.
  #
  # @param name [String] The operator name
  # @return [String] Aggressively normalised key
  #
  # @example
  #   aggressive_canonical_key("Qantas Airways")                    # => "qantas"
  #   aggressive_canonical_key("Qantas Airlines")                   # => "qantas"
  #   aggressive_canonical_key("Virgin Australia")                  # => "virginaustralia"
  #   aggressive_canonical_key("Virgin Australia Regional Airlines")# => "virginaustraliaregional"
  #   aggressive_canonical_key("QantasLink")                        # => "qantaslink"
  def aggressive_canonical_key(name)
    return '' if name.blank?

    key = name.to_s.strip

    # Remove corporate suffixes
    key = key.sub(CORPORATE_SUFFIX_PATTERN, '')

    # Remove common terms
    key = key.gsub(COMMON_TERMS_PATTERN, '')

    # Normalise to lowercase and remove non-alphanumeric
    key.downcase.gsub(/[^a-z0-9]/, '')
  end

  # Scores a name for quality/descriptiveness.
  # Higher score = better name to keep.
  #
  # @param name [String] The operator name
  # @param has_icao [Boolean] Whether the operator has an ICAO code
  # @param has_iata [Boolean] Whether the operator has an IATA code
  # @return [Integer] Quality score
  #
  # @example
  #   name_quality_score("Qantas Airways", has_icao: true, has_iata: true)  # => high score
  #   name_quality_score("QANTAS", has_icao: false, has_iata: false)        # => low score
  def name_quality_score(name, has_icao: false, has_iata: false)
    return 0 if name.blank?

    score = 0

    # Strongly prefer operators with codes (they're from authoritative sources)
    score += 200 if has_icao
    score += 100 if has_iata

    # Prefer proper case over ALL CAPS
    if name == name.upcase && name.length > 3
      score -= 50  # Penalise ALL CAPS (looks like data entry, not official)
    elsif name.match?(/\b[A-Z][a-z]+/)
      score += 30  # Reward proper title case
    end

    # Prefer names with descriptive terms
    score += 20 if name.match?(COMMON_TERMS_PATTERN)

    # Prefer longer names (more descriptive), but cap the bonus
    score += [name.length, 30].min

    # Penalise names that are just abbreviations
    score -= 30 if name.length < 5 && !name.match?(/[a-z]/)

    # Prefer names with proper punctuation
    score += 10 if name.include?(' ')

    score
  end

  # Picks the best name from a list of alternatives.
  #
  # @param candidates [Array<Hash>] List of { name:, has_icao:, has_iata: } hashes
  # @return [String, nil] The best name to use
  #
  # @example
  #   candidates = [
  #     { name: "QANTAS PTY LTD", has_icao: false, has_iata: false },
  #     { name: "Qantas Airways", has_icao: true, has_iata: true }
  #   ]
  #   best_name_from(candidates)  # => "Qantas Airways"
  def best_name_from(candidates)
    return nil if candidates.blank?

    candidates.compact.max_by do |c|
      name_quality_score(c[:name], has_icao: c[:has_icao], has_iata: c[:has_iata])
    end&.dig(:name)
  end

  # Checks if two operators should NOT be merged (genuinely different).
  # Returns true if they should be kept separate.
  #
  # @param op1 [Hash] First operator { name:, icao_code:, iata_code: }
  # @param op2 [Hash] Second operator { name:, icao_code:, iata_code: }
  # @return [Boolean] True if these are different operators
  #
  # @example
  #   # Same operator, different naming
  #   different_operators?(
  #     { name: "Qantas", icao_code: "QFA", iata_code: "QF" },
  #     { name: "Qantas Airways Ltd", icao_code: "QFA", iata_code: "QF" }
  #   )  # => false (same ICAO/IATA, safe to merge)
  #
  #   # Different operators with same name
  #   different_operators?(
  #     { name: "Air Express", icao_code: "AEJ", iata_code: nil },
  #     { name: "Air Express", icao_code: "AEQ", iata_code: nil }
  #   )  # => true (different ICAO codes, keep separate)
  def different_operators?(op1, op2)
    return false if op1.blank? || op2.blank?

    icao1 = op1[:icao_code].presence
    icao2 = op2[:icao_code].presence
    iata1 = op1[:iata_code].presence
    iata2 = op2[:iata_code].presence

    # If both have ICAO codes and they differ, definitely different operators
    return true if icao1 && icao2 && icao1 != icao2

    # If both have IATA codes and they differ, probably different operators
    # (unless one is a codeshare, but we'll treat as different to be safe)
    return true if iata1 && iata2 && iata1 != iata2

    # If codes match (or one is missing), they're likely the same operator
    false
  end

  # Normalises an operator name for display (not for matching).
  # Applies consistent formatting without losing information.
  #
  # @param name [String] The operator name
  # @return [String] Normalised name for display
  #
  # @example
  #   normalise_for_display("QANTAS AIRWAYS PTY LTD")  # => "Qantas Airways Pty Ltd"
  def normalise_for_display(name)
    return '' if name.blank?

    # Handle ALL CAPS names
    name = name.titleize if name == name.upcase && name.length > 3

    # Normalise corporate suffix casing
    name = name.sub(/\bpty\b/i, 'Pty')
    name = name.sub(/\bltd\.?\b/i, 'Ltd')
    name = name.sub(/\binc\.?\b/i, 'Inc')
    name = name.sub(/\bllc\b/i, 'LLC')
    name = name.sub(/\bgmbh\b/i, 'GmbH')
    name = name.sub(/\bplc\b/i, 'PLC')

    name.strip
  end
end
