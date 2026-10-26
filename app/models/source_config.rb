# frozen_string_literal: true

# Centralised trust configuration for all data sources.
#
# This class defines the trust scores and field-specific overrides for each source type.
# The SourceTrustScore table can provide runtime overrides, but this file is the primary
# source of truth and supports dynamic modifiers (lambdas) that can't be stored in the DB.
#
# The configuration includes:
# - base_trust: The default trust score for all fields from this source (0-100)
# - field_overrides: Field-specific trust scores that differ from the base
# - modifiers: Dynamic adjustments based on record attributes (lambdas)
#
# @example Looking up configuration for a source
#   config = SourceConfig.for('VRSDataOperatorSource')
#   config[:base_trust]  # => 80
#
# @example With field override
#   config = SourceConfig.for('CASAAircraftSource')
#   config[:field_overrides][:serial_number]  # => 95
class SourceConfig
  # Trust score constants for clarity
  VERY_HIGH_TRUST = 95
  HIGH_TRUST = 85
  MODERATE_HIGH_TRUST = 80
  MODERATE_TRUST = 70
  MODERATE_LOW_TRUST = 60
  LOW_TRUST = 40
  DEFAULT_TRUST = 50

  # Configuration for all known source types.
  # Each source has:
  # - base_trust: Default trust for all fields
  # - field_overrides: Hash of field_name => trust_score for field-specific values
  # - modifiers: Hash of field_name => { filter:, adjust: } for dynamic adjustments
  CONFIGS = {
    # === Operator Sources ===

    # VRS Data is community-maintained but well-curated
    'VRSDataOperatorSource' => {
      base_trust: MODERATE_HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OpenTravel is official IATA data; names are particularly reliable
    'OpenTravelOperatorSource' => {
      base_trust: MODERATE_TRUST,
      field_overrides: {
        name: HIGH_TRUST
      },
      modifiers: {}
    }.freeze,

    # OpenFlights operator data - community-sourced, less reliable
    'OpenFlightsOperatorSource' => {
      base_trust: MODERATE_LOW_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # === Aircraft Type Sources ===

    # ICAO official aircraft type database - authoritative source
    'CfappsICAOIntAircraftTypeSource' => {
      base_trust: VERY_HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # VRS aircraft type data - community-maintained, decent quality
    'VRSAircraftTypeSource' => {
      base_trust: MODERATE_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OpenFlights aircraft type data - older dataset, less reliable
    'OpenFlightsAircraftTypeSource' => {
      base_trust: MODERATE_LOW_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # === Manufacturer Sources ===

    # ICAO manufacturer data - authoritative
    'CfappsIcaoIntManufacturerSource' => {
      base_trust: VERY_HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OpenSky manufacturer data - community-sourced
    'OpenskyManufacturerSource' => {
      base_trust: MODERATE_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # === Country Sources ===

    # OpenTravel country data - official IATA source
    'OpenTravelCountrySource' => {
      base_trust: MODERATE_HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OurAirports country data - well-maintained
    'OurAirportsCountrySource' => {
      base_trust: MODERATE_HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OpenFlights country data - older dataset
    'OpenFlightsCountrySource' => {
      base_trust: MODERATE_LOW_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # === Airport Sources ===

    # OurAirports is well-maintained and comprehensive
    'OurAirportsAirportSource' => {
      base_trust: HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # OpenFlights airport data - older, elevation data is unreliable
    'OpenFlightsAirportSource' => {
      base_trust: MODERATE_TRUST,
      field_overrides: {
        elevation: LOW_TRUST
      },
      modifiers: {}
    }.freeze,

    # === Runway Sources ===

    # OurAirports runway data - well-maintained
    'OurAirportsRunwaySource' => {
      base_trust: HIGH_TRUST,
      field_overrides: {},
      modifiers: {}
    }.freeze,

    # === Aircraft Sources ===

    # CASA (Civil Aviation Safety Authority, Australia) - official government source
    # Authoritative for Australian aircraft - registration, serial numbers, AND ownership
    'CASAAircraftSource' => {
      base_trust: HIGH_TRUST,
      field_overrides: {
        # CASA is THE authority for Australian aircraft ownership and registration
        serial_number: VERY_HIGH_TRUST,
        owner: VERY_HIGH_TRUST,
        operator: HIGH_TRUST,
        operator_name: HIGH_TRUST
      },
      modifiers: {
        # Australian-registered aircraft (ICAO starting with 7C) get a trust boost
        icao: {
          filter: ->(record) { record.respond_to?(:icao) && record.icao&.match?(/\A7C/i) },
          adjust: ->(trust) { [trust + 10, 100].min }
        }
      }
    }.freeze,

    # CAANZ (Civil Aviation Authority of New Zealand) - official government source
    # Authoritative for New Zealand aircraft
    'CAANZAircraftSource' => {
      base_trust: HIGH_TRUST,
      field_overrides: {
        serial_number: VERY_HIGH_TRUST,
        owner: VERY_HIGH_TRUST,
        operator: HIGH_TRUST,
        operator_name: HIGH_TRUST
      },
      modifiers: {
        # NZ-registered aircraft (ICAO starting with C8) get a trust boost
        icao: {
          filter: ->(record) { record.respond_to?(:icao) && record.icao&.match?(/\AC8/i) },
          adjust: ->(trust) { [trust + 10, 100].min }
        }
      }
    }.freeze,

    # OpenSky aircraft data - large community-sourced database
    # Good for general data, but ownership info can be outdated
    'OpenskyAircraftSource' => {
      base_trust: MODERATE_LOW_TRUST,
      field_overrides: {
        serial_number: MODERATE_TRUST,
        # Owner data from OpenSky is often outdated
        owner: LOW_TRUST
      },
      modifiers: {}
    }.freeze,

    # VRS aircraft data - community-maintained, operator info is decent
    'VRSAircraftSource' => {
      base_trust: MODERATE_LOW_TRUST,
      field_overrides: {
        operator_name: MODERATE_HIGH_TRUST
      },
      modifiers: {}
    }.freeze
  }.freeze

  # The default configuration used when a source type is not explicitly configured.
  DEFAULT_CONFIG = {
    base_trust: DEFAULT_TRUST,
    field_overrides: {},
    modifiers: {}
  }.freeze

  # Returns the configuration for a given source class name.
  #
  # @param source_class_name [String] The source class name (e.g., "VRSDataOperatorSource")
  # @return [Hash] The configuration hash with :base_trust, :field_overrides, and :modifiers
  def self.for(source_class_name)
    # Strip any module prefixes if present (e.g., "Source::Operator::VRSDataOperatorSource")
    simple_name = source_class_name.to_s.demodulize
    CONFIGS[simple_name] || DEFAULT_CONFIG
  end

  # Returns the base trust score for a source, without field overrides.
  #
  # @param source_class_name [String] The source class name
  # @return [Integer] The base trust score (0-100)
  def self.base_trust_for(source_class_name)
    self.for(source_class_name)[:base_trust]
  end

  # Returns the trust score for a specific field from a source.
  # Checks field_overrides first, falls back to base_trust.
  #
  # @param source_class_name [String] The source class name
  # @param field_name [Symbol, String] The field name
  # @return [Integer] The trust score for this field
  def self.trust_for_field(source_class_name, field_name)
    config = self.for(source_class_name)
    field_key = field_name.to_sym

    config[:field_overrides][field_key] || config[:base_trust]
  end

  # Returns the modifiers for a source.
  #
  # @param source_class_name [String] The source class name
  # @return [Hash] The modifiers hash
  def self.modifiers_for(source_class_name)
    self.for(source_class_name)[:modifiers]
  end

  # Checks if a source type is explicitly configured.
  #
  # @param source_class_name [String] The source class name
  # @return [Boolean]
  def self.configured?(source_class_name)
    simple_name = source_class_name.to_s.demodulize
    CONFIGS.key?(simple_name)
  end

  # Returns all configured source types.
  #
  # @return [Array<String>] List of source class names
  def self.all_sources
    CONFIGS.keys
  end
end
