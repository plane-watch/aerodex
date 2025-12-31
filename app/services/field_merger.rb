# frozen_string_literal: true

# Merges values from multiple sources for a single field, selecting the best value
# based on trust scores.
#
# The FieldMerger evaluates all provided sources, calculates their trust scores,
# and returns the value from the highest-trusted source. It also provides
# provenance information for tracking.
#
# Data quality filters are applied to treat invalid values as missing:
# - elevation/altitude: Zero values are treated as missing (not sea level)
#
# Conflict detection uses tolerances for numeric fields:
# - latitude/longitude: Differences < 0.001 degrees (~100m) are not conflicts
#
# @example Basic usage
#   merger = FieldMerger.new(
#     sources: [vrs_record, otd_record],
#     field: :name,
#     entity_type: 'Operator'
#   )
#   merger.best_value      # => "Qantas Airways"
#   merger.best_source     # => <VRSDataOperatorSource>
#   merger.best_confidence # => 80
#
# @example Getting provenance for storage
#   provenance = merger.provenance_hash
#   # => {
#   #   "source_type" => "VRSDataOperatorSource",
#   #   "source_id" => 123,
#   #   "confidence" => 80,
#   #   "combined_at" => "2024-12-24T10:30:00Z"
#   # }
class FieldMerger
  attr_reader :sources, :field, :entity_type

  # Fields where zero should be treated as missing data (not a valid value)
  ZERO_IS_MISSING_FIELDS = %w[elevation altitude].freeze

  # Coordinate fields that use tolerance-based conflict detection
  COORDINATE_FIELDS = %w[latitude longitude].freeze

  # Tolerance for coordinate comparisons (~100m at the equator)
  COORDINATE_TOLERANCE = 0.001

  # Represents a source with its calculated trust score and field value.
  SourceCandidate = Struct.new(:source, :value, :trust_score, keyword_init: true)

  # Initialises the merger.
  #
  # @param sources [Array<ApplicationRecord>] The source records to evaluate
  # @param field [Symbol, String] The field name to merge
  # @param entity_type [String] The canonical entity type (e.g., "Operator")
  def initialize(sources:, field:, entity_type:)
    @sources = Array(sources).compact
    @field = field.to_s
    @entity_type = entity_type
    @candidates = nil
  end

  # Returns the best value for this field from the highest-trusted source.
  #
  # @return [Object, nil] The value from the winning source, or nil if no sources
  def best_value
    winning_candidate&.value
  end

  # Returns the source record that provided the best value.
  #
  # @return [ApplicationRecord, nil] The winning source record
  def best_source
    winning_candidate&.source
  end

  # Returns the trust/confidence score of the winning source.
  #
  # @return [Integer, nil] The trust score (0-100)
  def best_confidence
    winning_candidate&.trust_score
  end

  # Returns a hash suitable for storing in the field_provenance column.
  #
  # @return [Hash, nil] The provenance hash or nil if no sources
  def provenance_hash
    return nil unless winning_candidate

    {
      'source_type' => winning_candidate.source.class.name.demodulize,
      'source_id' => winning_candidate.source.id,
      'confidence' => winning_candidate.trust_score,
      'combined_at' => Time.current.iso8601
    }
  end

  # Returns all candidates sorted by trust score (highest first).
  # Useful for debugging or logging conflicts.
  #
  # @return [Array<SourceCandidate>]
  def ranked_candidates
    candidates.sort_by { |c| -c.trust_score }
  end

  # Checks if there are conflicting values between sources.
  # For coordinate fields, uses tolerance-based comparison.
  #
  # @return [Boolean] True if sources have different non-nil values
  def has_conflict?
    values = candidates.map(&:value).compact

    return false if values.length <= 1

    # For coordinate fields, use tolerance-based comparison
    if COORDINATE_FIELDS.include?(field)
      return values_differ_beyond_tolerance?(values)
    end

    # For other fields, simple uniqueness check
    values.uniq.length > 1
  end

  # Returns details about any conflicts for logging.
  #
  # @return [Hash, nil] Conflict details or nil if no conflict
  def conflict_details
    return nil unless has_conflict?

    {
      field: field,
      entity_type: entity_type,
      candidates: ranked_candidates.map do |c|
        {
          source_type: c.source.class.name.demodulize,
          source_id: c.source.id,
          value: c.value,
          trust_score: c.trust_score
        }
      end,
      winner: {
        source_type: best_source.class.name.demodulize,
        value: best_value,
        trust_score: best_confidence
      }
    }
  end

  private

  # Returns the winning candidate (highest trust score with a non-nil value).
  #
  # @return [SourceCandidate, nil]
  def winning_candidate
    @winning_candidate ||= candidates
                           .select { |c| c.value.present? }
                           .max_by(&:trust_score)
  end

  # Builds and caches the list of candidates with their trust scores.
  #
  # @return [Array<SourceCandidate>]
  def candidates
    @candidates ||= sources.map do |source|
      value = extract_value(source)
      trust_score = calculate_trust(source)

      SourceCandidate.new(
        source: source,
        value: value,
        trust_score: trust_score
      )
    end
  end

  # Extracts the field value from a source record, applying data quality filters.
  #
  # @param source [ApplicationRecord] The source record
  # @return [Object, nil] The field value
  def extract_value(source)
    return nil unless source.respond_to?(field)

    value = source.public_send(field)

    # Handle blank strings as nil for consistency
    value = value.presence
    return nil if value.nil?

    # Apply data quality filters
    value = apply_data_quality_filters(value)

    value
  end

  # Applies data quality filters to a value based on the field type.
  # Returns nil if the value should be treated as missing.
  #
  # @param value [Object] The raw value
  # @return [Object, nil] The filtered value or nil if invalid
  def apply_data_quality_filters(value)
    # For elevation/altitude fields, treat zero as missing data
    # (zero is almost never a valid airport elevation - it would mean exactly at sea level)
    if ZERO_IS_MISSING_FIELDS.include?(field)
      return nil if value.respond_to?(:zero?) && value.zero?
    end

    value
  end

  # Checks if numeric values differ beyond the tolerance threshold.
  # Used for coordinate fields where small differences are not meaningful.
  #
  # @param values [Array<Numeric>] The values to compare
  # @return [Boolean] True if any pair differs beyond tolerance
  def values_differ_beyond_tolerance?(values)
    numeric_values = values.map { |v| v.respond_to?(:to_f) ? v.to_f : nil }.compact
    return false if numeric_values.length <= 1

    min_val = numeric_values.min
    max_val = numeric_values.max

    (max_val - min_val).abs > COORDINATE_TOLERANCE
  end

  # Calculates the trust score for a source.
  #
  # @param source [ApplicationRecord] The source record
  # @return [Integer] The trust score (0-100)
  def calculate_trust(source)
    TrustCalculator.new(source, field: field, entity_type: entity_type).calculate
  end
end