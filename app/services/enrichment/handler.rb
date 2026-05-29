# frozen_string_literal: true

module Enrichment
  # Base class for per-subject request handlers. Owns the request lifecycle:
  # parse the payload, dispatch to the subclass's #handle, and serialise the
  # result to a JSON string. Translates known and unknown failures into the
  # standard error replies so the service always returns a well-formed body.
  #
  # Subclasses implement #handle(request) and return a Ruby hash.
  class Handler
    # @param data [String, nil] The raw NATS message payload.
    # @return [String] The JSON reply body.
    def call(data)
      request = RequestParser.parse(data)
      handle(request).to_json
    rescue BadRequestError => e
      { error: e.message, code: 'bad_request' }.to_json
    rescue StandardError => e
      Rails.logger.error("[enrichment] #{self.class.name} failed: #{e.class}: #{e.message}")
      { error: 'internal', code: 'internal' }.to_json
    end

    private

    # @param request [Hash] The parsed, symbolised request.
    # @return [Hash] The response body to serialise.
    def handle(_request)
      raise NotImplementedError, "#{self.class.name} must implement #handle"
    end

    # Returns true when the request opted into the named extra (e.g. 'provenance').
    #
    # @param request [Hash]
    # @param key [String]
    # @return [Boolean]
    def include?(request, key)
      Array(request[:include]).map(&:to_s).include?(key.to_s)
    end
  end
end
