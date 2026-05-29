# frozen_string_literal: true

module Enrichment
  # Raised when an incoming request payload is malformed or missing required
  # fields. Handlers translate this into a `bad_request` reply rather than an
  # internal error.
  class BadRequestError < StandardError; end
end
