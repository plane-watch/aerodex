# frozen_string_literal: true

require 'test_helper'

class Enrichment::HandlerTest < ActiveSupport::TestCase
  # A minimal concrete handler used to exercise the base-class behaviour.
  class EchoHandler < Enrichment::Handler
    private

    def handle(request)
      raise Enrichment::BadRequestError, 'boom' if request[:fail] == 'bad'
      raise 'kaboom' if request[:fail] == 'internal'

      { found: true, echo: request[:value], provenance_requested: include?(request, 'provenance') }
    end
  end

  test 'parses, dispatches to handle, and returns a JSON string' do
    reply = EchoHandler.new.call('{"value":"hi"}')

    assert_equal({ 'found' => true, 'echo' => 'hi', 'provenance_requested' => false }, JSON.parse(reply))
  end

  test 'include? reflects the include array' do
    reply = EchoHandler.new.call('{"value":"hi","include":["provenance"]}')

    assert_equal true, JSON.parse(reply)['provenance_requested']
  end

  test 'translates BadRequestError into a bad_request reply' do
    reply = EchoHandler.new.call('{"fail":"bad"}')

    assert_equal({ 'error' => 'boom', 'code' => 'bad_request' }, JSON.parse(reply))
  end

  test 'translates malformed JSON into a bad_request reply' do
    reply = EchoHandler.new.call('{not json')

    assert_equal 'bad_request', JSON.parse(reply)['code']
  end

  test 'translates an unexpected error into an internal reply and logs it' do
    reply = EchoHandler.new.call('{"fail":"internal"}')

    assert_equal({ 'error' => 'internal', 'code' => 'internal' }, JSON.parse(reply))
  end
end
