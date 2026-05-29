# frozen_string_literal: true

module Enrichment
  # Serialises an Operator into the shared `operator` object. Includes a shallow
  # parent (name and codes only) for multi-unit organisations; the parent has no
  # nested parent or country, to bound the response size.
  class OperatorSerializer
    # @param operator [Operator, nil]
    # @return [Hash, nil]
    def self.call(operator)
      return nil if operator.nil?

      {
        name: operator.name,
        icao_code: operator.icao_code,
        iata_code: operator.iata_code,
        country: CountrySerializer.call(operator.country),
        parent: parent_summary(operator.parent_operator)
      }
    end

    # Builds the shallow parent summary, or nil when there is no parent.
    #
    # @param parent [Operator, nil]
    # @return [Hash, nil]
    def self.parent_summary(parent)
      return nil if parent.nil?

      {
        name: parent.name,
        icao_code: parent.icao_code,
        iata_code: parent.iata_code
      }
    end
    private_class_method :parent_summary
  end
end
