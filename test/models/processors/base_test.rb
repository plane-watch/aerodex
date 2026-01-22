# frozen_string_literal: true

require "test_helper"

class Processors::BaseTest < ActiveSupport::TestCase
  setup do
    # Clear any existing thread-local state
    Processors::Base.send(:current_batch=, nil)
    Processors::Base.send(:staged_records_cache=, nil)
  end

  teardown do
    Processors::Base.send(:current_batch=, nil)
    Processors::Base.send(:staged_records_cache=, nil)
  end

  # ---------------------------------------------------------------------------
  # staged_records_cache accessor tests
  # ---------------------------------------------------------------------------

  test "staged_records_cache returns nil by default" do
    assert_nil Processors::Base.staged_records_cache
  end

  test "staged_records_cache can be set and retrieved" do
    cache = { Operator => { icao_code: {} } }
    Processors::Base.send(:staged_records_cache=, cache)

    assert_equal cache, Processors::Base.staged_records_cache
  end

  test "staged_records_cache is thread-local" do
    Processors::Base.send(:staged_records_cache=, { main: true })

    thread_value = nil
    Thread.new do
      thread_value = Processors::Base.staged_records_cache
    end.join

    assert_nil thread_value, "Expected cache to be nil in other thread"
    assert_equal({ main: true }, Processors::Base.staged_records_cache)
  end

  # ---------------------------------------------------------------------------
  # index_staged_records_by tests
  # ---------------------------------------------------------------------------

  test "index_staged_records_by initialises cache structure for model and fields" do
    Processors::Base.send(:staged_records_cache=, {})

    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    expected = {
      Operator => {
        icao_code: {},
        name: {}
      }
    }
    assert_equal expected, Processors::Base.staged_records_cache
  end

  test "index_staged_records_by preserves existing cache entries" do
    existing_operator = Operator.new(icao_code: "QFA", name: "Qantas")
    Processors::Base.send(:staged_records_cache=, {
      Operator => {
        icao_code: { "qfa" => existing_operator }
      }
    })

    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    assert_equal existing_operator, Processors::Base.staged_records_cache[Operator][:icao_code]["qfa"]
    assert_equal({}, Processors::Base.staged_records_cache[Operator][:name])
  end

  test "index_staged_records_by can register multiple model classes" do
    Processors::Base.send(:staged_records_cache=, {})

    Processors::Base.index_staged_records_by(Operator, :icao_code)
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    assert Processors::Base.staged_records_cache.key?(Operator)
    assert Processors::Base.staged_records_cache.key?(Manufacturer)
  end
end
