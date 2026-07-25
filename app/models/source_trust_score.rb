# frozen_string_literal: true
# == Schema Information
#
# Table name: source_trust_scores
#
#  id          :integer          not null, primary key
#  entity_type :string           not null
#  source_type :string           not null
#  field_name  :string
#  base_trust  :integer          default(50), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  idx_source_trust_scores_unique  (entity_type,source_type,field_name) UNIQUE
#

# Stores database-level trust score overrides for source/entity/field combinations.
#
# This model allows administrators to override the default trust scores defined in SourceConfig.
# Trust scores are looked up with field-specific overrides taking precedence over defaults.
#
# @example Creating a default trust score for a source
#   SourceTrustScore.create!(
#     entity_type: 'Operator',
#     source_type: 'VRSDataOperatorSource',
#     base_trust: 80
#   )
#
# @example Creating a field-specific override
#   SourceTrustScore.create!(
#     entity_type: 'Operator',
#     source_type: 'OpenTravelOperatorSource',
#     field_name: 'name',
#     base_trust: 85  # OpenTravel names are more reliable than their default
#   )
class SourceTrustScore < ApplicationRecord
  # The canonical entity types that can have trust scores
  VALID_ENTITY_TYPES = %w[
    Operator
    Aircraft
    AircraftType
    Manufacturer
    Country
    Airport
    Runway
  ].freeze

  # Trust score boundaries
  MIN_TRUST = 0
  MAX_TRUST = 100
  DEFAULT_TRUST = 50

  validates :entity_type, presence: true, inclusion: { in: VALID_ENTITY_TYPES }
  validates :source_type, presence: true
  validates :base_trust, presence: true,
                         numericality: {
                           only_integer: true,
                           greater_than_or_equal_to: MIN_TRUST,
                           less_than_or_equal_to: MAX_TRUST
                         }
  validates :entity_type, uniqueness: { scope: %i[source_type field_name] }

  class << self
    # Looks up the trust score for a given entity type, source type, and optional field.
    # Uses an in-memory cache for performance during batch operations.
    #
    # @param entity_type [String] The canonical entity type (e.g., "Operator")
    # @param source_type [String] The source class name (e.g., "VRSDataOperatorSource")
    # @param field_name [String, nil] Optional field name for field-specific lookup
    # @return [Integer] The trust score (0-100)
    def trust_for(entity_type:, source_type:, field_name: nil)
      ensure_cache_loaded

      # First, try to find a field-specific override
      if field_name.present?
        field_key = cache_key(entity_type, source_type, field_name)
        return @trust_cache[field_key] if @trust_cache.key?(field_key)
      end

      # Fall back to the default for this source (field_name is nil)
      default_key = cache_key(entity_type, source_type, nil)
      return @trust_cache[default_key] if @trust_cache.key?(default_key)

      # If nothing found, return the system default
      DEFAULT_TRUST
    end

    # Convenience method to check if a specific override exists.
    # Uses the in-memory cache for performance.
    #
    # @param entity_type [String]
    # @param source_type [String]
    # @param field_name [String, nil]
    # @return [Boolean]
    def override_exists?(entity_type:, source_type:, field_name: nil)
      ensure_cache_loaded
      @trust_cache.key?(cache_key(entity_type, source_type, field_name))
    end

    # Clears the in-memory cache. Call this after modifying trust scores.
    def clear_cache!
      @trust_cache = nil
    end

    private

    # Loads all trust scores into memory for O(1) lookups.
    def ensure_cache_loaded
      return if @trust_cache

      @trust_cache = {}
      all.find_each do |score|
        key = cache_key(score.entity_type, score.source_type, score.field_name)
        @trust_cache[key] = score.base_trust
      end
    end

    # Generates a cache key for the given parameters.
    #
    # @param entity_type [String]
    # @param source_type [String]
    # @param field_name [String, nil]
    # @return [String]
    def cache_key(entity_type, source_type, field_name)
      "#{entity_type}:#{source_type}:#{field_name}"
    end
  end
end
