# frozen_string_literal: true

# Calculates the final trust score for a source record and field combination.
#
# The calculation follows this precedence:
# 1. Database override (SourceTrustScore table) - for admin customisation
# 2. SourceConfig field-specific override
# 3. SourceConfig base trust
# 4. System default (50)
#
# After determining the base score, any applicable modifiers are applied.
#
# @example Basic usage
#   calculator = TrustCalculator.new(vrs_record, field: :name, entity_type: 'Operator')
#   score = calculator.calculate  # => 80
#
# @example With modifier applied
#   calculator = TrustCalculator.new(casa_record, field: :icao, entity_type: 'Aircraft')
#   score = calculator.calculate  # => 95 (85 base + 10 for Australian aircraft)
class TrustCalculator
  attr_reader :source_record, :field, :entity_type

  # Initialises the calculator.
  #
  # @param source_record [ApplicationRecord] The source record providing the data
  # @param field [Symbol, String] The field name being evaluated
  # @param entity_type [String] The canonical entity type (e.g., "Operator", "Aircraft")
  def initialize(source_record, field:, entity_type:)
    @source_record = source_record
    @field = field.to_s
    @entity_type = entity_type
  end

  # Calculates the final trust score for this source/field combination.
  #
  # @return [Integer] The final trust score (0-100)
  def calculate
    base_score = determine_base_score
    apply_modifiers(base_score)
  end

  # Returns the source class name for logging/debugging.
  #
  # @return [String]
  def source_type
    @source_type ||= source_record.class.name.demodulize
  end

  private

  # Determines the base trust score before modifiers are applied.
  # Checks database overrides first, then falls back to SourceConfig.
  #
  # @return [Integer]
  def determine_base_score
    # Step 1: Check for a database override (field-specific)
    db_override = SourceTrustScore.trust_for(
      entity_type: entity_type,
      source_type: source_type,
      field_name: field
    )

    # If we got a non-default value from the database, use it
    if SourceTrustScore.override_exists?(entity_type: entity_type, source_type: source_type, field_name: field)
      return db_override
    end

    # Check for a database default (no field specified)
    if SourceTrustScore.override_exists?(entity_type: entity_type, source_type: source_type, field_name: nil)
      db_default = SourceTrustScore.trust_for(entity_type: entity_type, source_type: source_type)
      # But still check for field override in SourceConfig
      config = SourceConfig.for(source_type)
      field_override = config[:field_overrides][field.to_sym]
      return field_override if field_override

      return db_default
    end

    # Step 2: Fall back to SourceConfig (which handles field overrides internally)
    SourceConfig.trust_for_field(source_type, field)
  end

  # Applies any dynamic modifiers to the base score.
  #
  # @param base_score [Integer] The score before modifiers
  # @return [Integer] The adjusted score (clamped to 0-100)
  def apply_modifiers(base_score)
    modifiers = SourceConfig.modifiers_for(source_type)
    return base_score if modifiers.empty?

    adjusted_score = base_score

    # Check for a field-specific modifier
    field_modifier = modifiers[field.to_sym]
    if field_modifier
      adjusted_score = apply_single_modifier(adjusted_score, field_modifier)
    end

    # Also check for general modifiers that might apply
    modifiers.each do |modifier_field, modifier_config|
      # Skip the field-specific one we already applied
      next if modifier_field == field.to_sym

      # Apply general modifiers that match their filter
      if modifier_config[:filter].call(source_record)
        adjusted_score = modifier_config[:adjust].call(adjusted_score)
      end
    end

    # Ensure the score stays within bounds
    adjusted_score.clamp(0, 100)
  end

  # Applies a single modifier if its filter matches.
  #
  # @param score [Integer] The current score
  # @param modifier [Hash] The modifier configuration with :filter and :adjust
  # @return [Integer] The adjusted score
  def apply_single_modifier(score, modifier)
    return score unless modifier[:filter].call(source_record)

    modifier[:adjust].call(score)
  end
end