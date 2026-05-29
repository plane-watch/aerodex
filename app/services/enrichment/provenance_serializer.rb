# frozen_string_literal: true

module Enrichment
  # Builds the opt-in `provenance` block for an entity that tracks field-level
  # provenance via HasFieldProvenance. Delegates to the model's existing
  # all_provenance_with_sources so the per-field shape stays consistent with the
  # rest of the application. Returns nil for records that do not track
  # provenance (e.g. Route), so the caller can omit the block entirely.
  class ProvenanceSerializer
    # @param record [ActiveRecord::Base]
    # @return [Hash, nil]
    def self.call(record)
      return nil unless record.respond_to?(:all_provenance_with_sources)

      record.all_provenance_with_sources
    end
  end
end
