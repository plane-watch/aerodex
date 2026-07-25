# frozen_string_literal: true

# Canonicalises aircraft type names for deduplication.
#
# Different data sources use different naming conventions for the same aircraft:
# - "An-148" vs "Antonov An-148" (manufacturer prefix)
# - "A-319neo" vs "A319neo" (hyphen variation)
# - "Skyraider" vs "A-1 Skyraider" (designation prefix)
#
# This concern provides methods to:
# 1. Generate a canonical key for grouping (merges duplicates)
# 2. Score names to pick the best/most descriptive one
# 3. Detect if two names are variants vs genuinely different types
#
# @example
#   canonical_name_key("Antonov An-148")  # => "an148"
#   canonical_name_key("An-148")          # => "an148"
#   # Both group together, we keep "Antonov An-148" as best name
module AircraftTypeNameCanonicalisation
  extend ActiveSupport::Concern

  # Known manufacturer names to strip for canonicalization
  MANUFACTURER_PREFIXES = /\A(
    Antonov|Airbus|Boeing|Embraer|Bombardier|Cessna|Beechcraft|Beech|Piper|
    De\sHavilland|Lockheed|Douglas|McDonnell|BAe|Hawker|SAAB|Fokker|ATR|
    Pilatus|Dassault|Gulfstream|Sikorsky|Bell|Eurocopter|Agusta|Leonardo|
    Mil|Kamov|Sukhoi|Tupolev|Ilyushin|Yakovlev|Mitsubishi|Kawasaki|
    Grumman|Northrop|Fairchild|Dornier|British\sAerospace|Short|CASA|
    IAI|Aermacchi|Aerospatiale|Sud\sAviation|Robin|Socata|Mooney|
    Cirrus|Diamond|Tecnam|Pipistrel|Extra|Zlin|Let|Aero|PZL
  )\s+/ix

  # Designation prefixes (military/variant prefixes) to normalize
  # These indicate the same base aircraft with different roles
  DESIGNATION_PREFIXES = /\A(
    [A-Z]{1,2}-\d+[A-Z]?\s+|  # A-1, F-16, etc.
    [A-Z]{2,3}\d+-\d+\s+|     # AW-109, AS-350, etc.
    [A-Z]-\d+\s+              # A-1, C-130, etc.
  )/ix

  # Variant indicator patterns - each category checked separately for clarity
  # Executive variants (BBJ, ACJ) - may be followed by model numbers (BBJ2, ACJ320)
  EXECUTIVE_INDICATOR = /\b(BBJ\d*|ACJ\d*)\b/i
  # Cargo variants
  CARGO_INDICATOR = /\b(Freighter|Cargo|BCF|SF)\b/i
  # Range variants - ER/LR must follow a digit to avoid matching "Dornier"
  RANGE_INDICATOR = /\d(ER|LR)\b/i
  # Generation variants - neo suffix or standalone MAX
  GENERATION_INDICATOR = /neo\b|\bMAX\b/i
  # Special variants
  SPECIAL_INDICATOR = /\b(XWB)\b/i

  # Generates a canonical key for grouping similar names.
  # Names that produce the same key will be merged.
  #
  # @param name [String] The aircraft type name
  # @return [String] Normalized key for grouping
  #
  # @example
  #   canonical_name_key("Antonov An-148")  # => "an148"
  #   canonical_name_key("An-148")          # => "an148"
  #   canonical_name_key("A-319neo")        # => "a319neo"
  #   canonical_name_key("A319neo")         # => "a319neo"
  def canonical_name_key(name)
    return '' if name.blank?

    key = name.to_s.strip

    # Remove manufacturer prefix for canonicalization
    key = key.sub(MANUFACTURER_PREFIXES, '')

    # Remove designation prefix (e.g., "A-1 " from "A-1 Skyraider")
    key = key.sub(DESIGNATION_PREFIXES, '')

    # Normalize to lowercase, remove hyphens/spaces
    key = key.downcase.gsub(/[\s-]/, '')

    # Remove non-alphanumeric
    key.gsub(/[^a-z0-9]/, '')
  end

  # Scores a name for quality/descriptiveness.
  # Higher score = better name to keep.
  #
  # @param name [String] The aircraft type name
  # @return [Integer] Quality score
  #
  # @example
  #   name_quality_score("Antonov An-148")  # => 150 (has manufacturer)
  #   name_quality_score("An-148")          # => 50 (has designation)
  #   name_quality_score("Mriya")           # => 0 (just nickname)
  def name_quality_score(name)
    return 0 if name.blank?

    score = 0

    # Prefer names with manufacturer prefix
    score += 100 if name.match?(MANUFACTURER_PREFIXES)

    # Prefer names with model designation (An-148, 737-800, etc.)
    score += 50 if name.match?(/\b[A-Z]{1,3}[\s-]?\d{2,4}/i)

    # Prefer names with series/variant info
    score += 25 if name.match?(/\d{3}/)

    # Prefer longer names (more descriptive)
    score += [name.length, 30].min

    # Penalize names that are just nicknames
    score -= 50 if name.length < 10 && !name.match?(/\d/)

    score
  end

  # Picks the best name from a list of alternatives.
  #
  # @param names [Array<String>] List of name variations
  # @return [String] The best name to use
  def best_name_from(names)
    return nil if names.blank?

    names.compact.max_by { |n| name_quality_score(n) }
  end

  # Checks if two names represent genuinely different variants.
  # Returns true if they should NOT be merged.
  #
  # @param name1 [String] First name
  # @param name2 [String] Second name
  # @return [Boolean] True if these are different variants
  #
  # @example
  #   different_variants?("737-700", "737-800")      # => true (different series)
  #   different_variants?("737-800", "737-800 BBJ")  # => true (commercial vs exec)
  #   different_variants?("An-148", "Antonov An-148") # => false (same aircraft)
  def different_variants?(name1, name2)
    return false if name1.blank? || name2.blank?

    # Extract the variant identifier from different naming patterns:
    # - Boeing: "737-800" -> "800"
    # - Airbus: "A320-200" -> "200"
    # - Military: "SA-341" -> "341", "L-39" -> "39"
    # - General: "G-802" -> "802", "D-112" -> "112"
    variant1 = extract_variant_number(name1)
    variant2 = extract_variant_number(name2)

    # If both have variant numbers and they differ, these are different variants
    return true if variant1 && variant2 && variant1 != variant2

    # Check for variant indicators that differ (BBJ, ACJ, Freighter, etc.)
    variants1 = extract_variant_indicators(name1)
    variants2 = extract_variant_indicators(name2)

    # If one has BBJ/ACJ/etc and the other doesn't, they're different
    return true if (variants1.any? || variants2.any?) && (variants1.sort != variants2.sort)

    false
  end

  private

  # Extracts the variant number from an aircraft name.
  # Handles multiple naming conventions:
  # - "737-800" -> "800" (Boeing style)
  # - "A320-200" -> "200" (Airbus style)
  # - "SA-341" -> "341" (military designation)
  # - "L-39" -> "39" (short military designation)
  #
  # @param name [String] The aircraft name
  # @return [String, nil] The variant number or nil if not found
  def extract_variant_number(name)
    # Pattern 1: Boeing/Airbus style (digits-digits or letter+digits-digits)
    # Matches: 737-800, 747-8, A320-200, A350-1000
    if (match = name.match(/\b[A-Z]?\d{2,3}-(\d{1,4})\b/i))
      return match[1]
    end

    # Pattern 2: Military/general designation (letters-digits)
    # Matches: SA-341, L-39, G-802, D-112
    if (match = name.match(/\b[A-Z]{1,3}-(\d{1,4})\b/i))
      return match[1]
    end

    nil
  end

  # Extracts variant indicators from an aircraft name.
  # Each category is checked separately for clarity and to avoid false positives.
  #
  # @param name [String] The aircraft name
  # @return [Array<String>] List of variant categories present (e.g., ["executive", "cargo"])
  def extract_variant_indicators(name)
    indicators = []

    # Check each category - we return category names, not the actual matches,
    # so that "BBJ" and "BBJ2" are treated as the same category
    indicators << 'executive' if name.match?(EXECUTIVE_INDICATOR)
    indicators << 'cargo' if name.match?(CARGO_INDICATOR)
    indicators << 'range' if name.match?(RANGE_INDICATOR)
    indicators << 'generation' if name.match?(GENERATION_INDICATOR)
    indicators << 'special' if name.match?(SPECIAL_INDICATOR)

    indicators
  end
end
