# frozen_string_literal: true

# Normalises aircraft model/variant names to their base commercial designations.
#
# Aircraft manufacturers use customer codes and configuration suffixes that make
# matching difficult. For example:
# - Boeing 737-8SA = 737-800 built for SilkAir (8 = 800 series, SA = customer)
# - Boeing 737-8FE = 737-800 built for Virgin Australia
# - Airbus A320-232 = A320 with specific engine/customer config
#
# This concern provides methods to:
# 1. Extract base model from variant codes (737-8SA → 737-800)
# 2. Identify non-commercial variants (BBJ, ACJ, military) for deprioritization
#
# @see https://en.wikipedia.org/wiki/List_of_Boeing_customer_codes
module AircraftModelNormalisation
  extend ActiveSupport::Concern

  # Boeing customer code pattern: 737-8XX where XX is 2 alphanumeric chars
  # The digit after the dash indicates the series (7=700, 8=800, 9=900)
  BOEING_NARROWBODY_PATTERN = /\A737-([789])(\w{2})\z/i
  BOEING_747_PATTERN = /\A747-([48])(\w{2})\z/i
  BOEING_757_PATTERN = /\A757-([23])(\w{2})\z/i
  BOEING_767_PATTERN = /\A767-([234])(\w{2})\z/i
  BOEING_777_PATTERN = /\A777-([23])(\w{2})\z/i
  BOEING_787_PATTERN = /\A787-([89]|10)(\w{0,2})\z/i

  # Airbus pattern: A3XX-YZZ where YZZ is engine/customer code
  AIRBUS_SINGLE_AISLE_PATTERN = /\A(A3[12][890])-\d{3}\z/i
  AIRBUS_A330_PATTERN = /\A(A330)-([23])\d{2}\z/i
  AIRBUS_A340_PATTERN = /\A(A340)-([2356])\d{2}\z/i
  AIRBUS_A350_PATTERN = /\A(A350)-([89]|10)\d{2}\z/i
  AIRBUS_A380_PATTERN = /\A(A380)-\d{3}\z/i

  # Non-commercial variants that should be deprioritized for airline aircraft
  EXECUTIVE_VARIANTS = /\b(BBJ\d?|ACJ[\d\s-]*|ACJ\s*neo|Business\s*Express|Corporate|Executive|VIP|Private|Prestige)\b/i
  MILITARY_VARIANTS = /\b(P-8|KC-\d+|E-[478]|C-40|C-32|VC-25|AEW|Poseidon|Tanker|Wedgetail)\b/i
  FREIGHTER_VARIANTS = /\b(Freighter|BCF|BDSF|SF|Cargo)\b/i

  # Patterns to detect if source model is itself an executive/military variant
  SOURCE_IS_EXECUTIVE = /\b(BBJ|ACJ|Business\s*Jet|Corporate\s*Jet|VIP)\b/i
  SOURCE_IS_MILITARY = /\b(P-8|KC-|E-[478]|C-40|C-32|VC-25|AEW|Poseidon|Tanker|Wedgetail)\b/i

  # Normalises an aircraft model string to its base commercial designation.
  #
  # @param model [String] The model/variant string from source data
  # @return [String, nil] The normalised base model, or nil if no normalisation applies
  #
  # @example Boeing variants
  #   normalise_to_base_model("737-8SA")  # => "737-800"
  #   normalise_to_base_model("737-8FE")  # => "737-800"
  #   normalise_to_base_model("777-3ZG")  # => "777-300"
  #
  # @example Airbus variants
  #   normalise_to_base_model("A320-232") # => "A320"
  #   normalise_to_base_model("A330-343") # => "A330-300"
  def normalise_to_base_model(model)
    return nil if model.blank?

    model = model.strip

    # Try Boeing patterns
    result = normalise_boeing_model(model)
    return result if result

    # Try Airbus patterns
    result = normalise_airbus_model(model)
    return result if result

    # No normalisation needed/possible
    nil
  end

  # Checks if a model name represents a non-commercial variant.
  # Used to deprioritize BBJ, ACJ, military variants when matching airline aircraft.
  #
  # @param name [String] The aircraft type name
  # @return [Boolean] True if this is a non-commercial variant
  #
  # @example
  #   non_commercial_variant?("Boeing BBJ2")     # => true
  #   non_commercial_variant?("Airbus ACJ320")   # => true
  #   non_commercial_variant?("Boeing 737-800")  # => false
  def non_commercial_variant?(name)
    return false if name.blank?

    name.match?(EXECUTIVE_VARIANTS) || name.match?(MILITARY_VARIANTS)
  end

  # Checks if a model name represents a freighter variant.
  #
  # @param name [String] The aircraft type name
  # @return [Boolean] True if this is a freighter variant
  def freighter_variant?(name)
    return false if name.blank?

    name.match?(FREIGHTER_VARIANTS)
  end

  private

  # Normalises Boeing model variants to base designations.
  #
  # @param model [String] The model string
  # @return [String, nil] Normalised model or nil
  def normalise_boeing_model(model)
    case model
    # 737 family: 737-8SA → 737-800
    when BOEING_NARROWBODY_PATTERN
      series = ::Regexp.last_match(1)
      "737-#{series}00"

    # 747 family: 747-4XX → 747-400, 747-8XX → 747-8
    when BOEING_747_PATTERN
      series = ::Regexp.last_match(1)
      series == '8' ? '747-8' : "747-#{series}00"

    # 757 family: 757-2XX → 757-200
    when BOEING_757_PATTERN
      series = ::Regexp.last_match(1)
      "757-#{series}00"

    # 767 family: 767-3XX → 767-300
    when BOEING_767_PATTERN
      series = ::Regexp.last_match(1)
      "767-#{series}00"

    # 777 family: 777-3XX → 777-300
    when BOEING_777_PATTERN
      series = ::Regexp.last_match(1)
      "777-#{series}00"

    # 787 family: already uses simple designations (787-8, 787-9, 787-10)
    when BOEING_787_PATTERN
      series = ::Regexp.last_match(1)
      "787-#{series}"

    # 737 MAX variants
    when /737[\s-]?(MAX\s*)?([789]|10)(\s*MAX)?/i
      series = ::Regexp.last_match(2)
      "737 MAX #{series}"

    else
      nil
    end
  end

  # Normalises Airbus model variants to base designations.
  #
  # @param model [String] The model string
  # @return [String, nil] Normalised model or nil
  def normalise_airbus_model(model)
    case model
    # A318/A319/A320/A321: A320-232 → A320
    when AIRBUS_SINGLE_AISLE_PATTERN
      ::Regexp.last_match(1).upcase

    # A330: A330-343 → A330-300
    when AIRBUS_A330_PATTERN
      series = ::Regexp.last_match(2)
      "A330-#{series}00"

    # A340: A340-642 → A340-600
    when AIRBUS_A340_PATTERN
      series = ::Regexp.last_match(2)
      "A340-#{series}00"

    # A350: A350-941 → A350-900
    when AIRBUS_A350_PATTERN
      series = ::Regexp.last_match(2)
      series == '10' ? 'A350-1000' : "A350-#{series}00"

    # A380: A380-841 → A380-800
    when AIRBUS_A380_PATTERN
      'A380-800'

    # A320neo family - preserve neo suffix
    when /\A(A3[12][890])[\s-]?\d*[\s-]?(neo)\z/i
      "#{::Regexp.last_match(1).upcase}neo"

    else
      nil
    end
  end
end