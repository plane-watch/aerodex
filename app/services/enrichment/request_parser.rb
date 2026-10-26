# frozen_string_literal: true

module Enrichment
  # Parses a raw NATS message payload (a JSON object) into a symbolised hash.
  # Every enrichment request is a JSON object; anything else is a bad request.
  class RequestParser
    # @param data [String, nil] The raw message payload.
    # @return [Hash] The parsed request with symbolised keys.
    # @raise [BadRequestError] If the payload is blank, not valid JSON, or not an object.
    def self.parse(data)
      raise BadRequestError, 'empty request payload' if data.nil? || data.empty?

      parsed = JSON.parse(data)
      raise BadRequestError, 'request must be a JSON object' unless parsed.is_a?(Hash)

      parsed.deep_symbolize_keys
    rescue JSON::ParserError => e
      raise BadRequestError, "invalid JSON: #{e.message}"
    end
  end
end
