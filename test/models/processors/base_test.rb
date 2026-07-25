# frozen_string_literal: true

require 'test_helper'

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

  test 'staged_records_cache returns nil by default' do
    assert_nil Processors::Base.staged_records_cache
  end

  test 'staged_records_cache can be set and retrieved' do
    cache = { Operator => { icao_code: {} } }
    Processors::Base.send(:staged_records_cache=, cache)

    assert_equal cache, Processors::Base.staged_records_cache
  end

  test 'staged_records_cache is thread-local' do
    Processors::Base.send(:staged_records_cache=, { main: true })

    thread_value = nil
    Thread.new do
      thread_value = Processors::Base.staged_records_cache
    end.join

    assert_nil thread_value, 'Expected cache to be nil in other thread'
    assert_equal({ main: true }, Processors::Base.staged_records_cache)
  end

  # ---------------------------------------------------------------------------
  # index_staged_records_by tests
  # ---------------------------------------------------------------------------

  test 'index_staged_records_by initialises cache structure for model and fields' do
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

  test 'index_staged_records_by preserves existing cache entries' do
    existing_operator = Operator.new(icao_code: 'QFA', name: 'Qantas')
    Processors::Base.send(:staged_records_cache=, {
      Operator => {
        icao_code: { 'qfa' => existing_operator }
      }
    })

    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    assert_equal existing_operator, Processors::Base.staged_records_cache[Operator][:icao_code]['qfa']
    assert_equal({}, Processors::Base.staged_records_cache[Operator][:name])
  end

  test 'index_staged_records_by can register multiple model classes' do
    Processors::Base.send(:staged_records_cache=, {})

    Processors::Base.index_staged_records_by(Operator, :icao_code)
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    assert Processors::Base.staged_records_cache.key?(Operator)
    assert Processors::Base.staged_records_cache.key?(Manufacturer)
  end

  # ---------------------------------------------------------------------------
  # cache_staged_record tests
  # ---------------------------------------------------------------------------

  test 'cache_staged_record indexes record by declared fields' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

    operator = Operator.new(icao_code: 'QFA', name: 'Qantas Airways')
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]['qfa']
    assert_equal operator, Processors::Base.staged_records_cache[Operator][:name]['qantas airways']
  end

  test 'cache_staged_record uses case-insensitive keys' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: 'QFA')
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]['qfa']
  end

  test 'cache_staged_record skips blank field values' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code, :iata_code)

    operator = Operator.new(icao_code: 'QFA', iata_code: nil)
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.staged_records_cache[Operator][:icao_code]['qfa']
    assert_empty Processors::Base.staged_records_cache[Operator][:iata_code]
  end

  test 'cache_staged_record does nothing if model not indexed' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    operator = Operator.new(icao_code: 'QFA')
    Processors::Base.cache_staged_record(operator)

    assert_not Processors::Base.staged_records_cache.key?(Operator)
  end

  test 'cache_staged_record overwrites existing entry for same key' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator1 = Operator.new(icao_code: 'QFA', name: 'Old Name')
    operator2 = Operator.new(icao_code: 'QFA', name: 'New Name')

    Processors::Base.cache_staged_record(operator1)
    Processors::Base.cache_staged_record(operator2)

    cached = Processors::Base.staged_records_cache[Operator][:icao_code]['qfa']
    assert_equal 'New Name', cached.name
  end

  # ---------------------------------------------------------------------------
  # find_in_staged_cache tests
  # ---------------------------------------------------------------------------

  test 'find_in_staged_cache returns cached record by single field' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: 'QFA', name: 'Qantas')
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: 'QFA')
    assert_equal operator, result
  end

  test 'find_in_staged_cache is case-insensitive' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: 'QFA')
    Processors::Base.cache_staged_record(operator)

    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: 'qfa')
    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: 'QFA')
    assert_equal operator, Processors::Base.find_in_staged_cache(Operator, icao_code: 'Qfa')
  end

  test 'find_in_staged_cache returns nil when not found' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: 'NOTFOUND')
    assert_nil result
  end

  test 'find_in_staged_cache handles array of values' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: 'QFA')
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: ['JST', 'QFA', 'SIA'])
    assert_equal operator, result
  end

  test 'find_in_staged_cache returns first match from array' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    qantas = Operator.new(icao_code: 'QFA', name: 'Qantas')
    jetstar = Operator.new(icao_code: 'JST', name: 'Jetstar')
    Processors::Base.cache_staged_record(qantas)
    Processors::Base.cache_staged_record(jetstar)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: ['JST', 'QFA'])
    assert_equal jetstar, result
  end

  test 'find_in_staged_cache returns nil if model not indexed' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Manufacturer, :icao_code)

    result = Processors::Base.find_in_staged_cache(Operator, icao_code: 'QFA')
    assert_nil result
  end

  test 'find_in_staged_cache returns nil if field not indexed' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    operator = Operator.new(icao_code: 'QFA', name: 'Qantas')
    Processors::Base.cache_staged_record(operator)

    result = Processors::Base.find_in_staged_cache(Operator, name: 'Qantas')
    assert_nil result
  end

  # ---------------------------------------------------------------------------
  # find_staged_or_persisted tests
  # ---------------------------------------------------------------------------

  test 'find_staged_or_persisted returns cached record if present' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    cached_operator = Operator.new(icao_code: 'TC1', name: 'Cached')
    Processors::Base.cache_staged_record(cached_operator)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: 'TC1')
    assert_equal cached_operator, result
  end

  test 'find_staged_or_persisted falls back to database' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    # Create a persisted operator
    db_operator = Operator.create!(icao_code: 'TD1', name: 'Database Operator')

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: 'TD1')
    assert_equal db_operator, result
  ensure
    Operator.where(icao_code: 'TD1').delete_all
  end

  test 'find_staged_or_persisted prefers cache over database' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    # Create persisted operator
    Operator.create!(icao_code: 'TB1', name: 'Database Version')

    # Cache a different record with same key
    cached_operator = Operator.new(icao_code: 'TB1', name: 'Cached Version')
    Processors::Base.cache_staged_record(cached_operator)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: 'TB1')
    assert_equal 'Cached Version', result.name
  ensure
    Operator.where(icao_code: 'TB1').delete_all
  end

  test 'find_staged_or_persisted returns nil when not found anywhere' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: 'ZZZ')
    assert_nil result
  end

  test 'find_staged_or_persisted handles array criteria for database' do
    Processors::Base.send(:staged_records_cache=, {})
    Processors::Base.index_staged_records_by(Operator, :icao_code)

    db_operator = Operator.create!(icao_code: 'TA1', name: 'Array Test')

    result = Processors::Base.find_staged_or_persisted(Operator, icao_code: ['ZZ1', 'TA1'])
    assert_equal db_operator, result
  ensure
    Operator.where(icao_code: 'TA1').delete_all
  end

  # ---------------------------------------------------------------------------
  # with_staged_batch cache lifecycle tests
  # ---------------------------------------------------------------------------

  test 'with_staged_batch initialises empty cache' do
    # Use a test processor class
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    cache_during_block = nil

    test_processor.with_staged_batch(entity_type: 'Test') do
      cache_during_block = Processors::Base.staged_records_cache
    end

    assert_equal({}, cache_during_block)
  end

  test 'with_staged_batch clears cache after completion' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    test_processor.with_staged_batch(entity_type: 'Test') do
      Processors::Base.index_staged_records_by(Operator, :icao_code)
      operator = Operator.new(icao_code: 'TEST')
      Processors::Base.cache_staged_record(operator)
    end

    assert_nil Processors::Base.staged_records_cache
  end

  test 'with_staged_batch clears cache on error' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    assert_raises(RuntimeError) do
      test_processor.with_staged_batch(entity_type: 'Test') do
        Processors::Base.index_staged_records_by(Operator, :icao_code)
        raise 'Test error'
      end
    end

    assert_nil Processors::Base.staged_records_cache
  end

  # ---------------------------------------------------------------------------
  # stage_change caching tests
  # ---------------------------------------------------------------------------

  test 'stage_change caches the record' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    test_processor.with_staged_batch(entity_type: 'Operator') do
      Processors::Base.index_staged_records_by(Operator, :icao_code)

      operator = Operator.new(icao_code: 'ST1', name: 'Stage Test')
      Processors::Base.stage_change(operator, operation: :create, identifier: 'ST1')

      cached = Processors::Base.find_in_staged_cache(Operator, icao_code: 'ST1')
      assert_equal operator, cached
    end
  end

  test 'stage_change caches update operations' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    existing = Operator.create!(icao_code: 'UT1', name: 'Old Name')

    test_processor.with_staged_batch(entity_type: 'Operator') do
      Processors::Base.index_staged_records_by(Operator, :icao_code)

      existing.name = 'New Name'
      Processors::Base.stage_change(existing, operation: :update, identifier: 'UT1')

      cached = Processors::Base.find_in_staged_cache(Operator, icao_code: 'UT1')
      assert_equal 'New Name', cached.name
    end
  ensure
    Operator.where(icao_code: 'UT1').delete_all
  end

  test 'stage_change merges update into existing create for same identifier' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    test_processor.with_staged_batch(entity_type: 'Operator') do
      Processors::Base.index_staged_records_by(Operator, :icao_code, :name)

      # Phase 1: Create a new operator and stage it
      operator = Operator.new(icao_code: 'ZMG', name: 'Original Name')
      Processors::Base.stage_change(operator, operation: :create, identifier: 'ZMG')

      # Verify the CREATE was staged
      batch = Processors::Base.current_batch
      assert_equal 1, batch.staged_changes.count
      assert_equal 'create', batch.staged_changes.first.operation

      # Phase 2: Find the cached operator and update it
      cached = Processors::Base.find_in_staged_cache(Operator, icao_code: 'ZMG')
      assert_not_nil cached

      cached.name = 'Updated Name'
      Processors::Base.stage_change(cached, operation: :update, identifier: 'ZMG')

      # Should still be just one staged change (the CREATE), not CREATE + UPDATE
      assert_equal 1, batch.staged_changes.count
      change = batch.staged_changes.first
      assert_equal 'create', change.operation

      # The CREATE's diff should have the updated name
      assert_equal [nil, 'Updated Name'], change.diff['name']

      # Summary should show 1 created, 0 updated
      assert_equal 1, batch.summary['created']
      assert_equal 0, batch.summary['updated']
    end
  end

  test 'stage_change does not merge if no existing create' do
    test_processor = Class.new(Processors::Base)
    test_processor.define_singleton_method(:name) { 'TestProcessor' }

    existing = Operator.create!(icao_code: 'ZNM', name: 'Old Name')

    test_processor.with_staged_batch(entity_type: 'Operator') do
      Processors::Base.index_staged_records_by(Operator, :icao_code)

      # Update a persisted record (no staged CREATE exists)
      existing.name = 'New Name'
      Processors::Base.stage_change(existing, operation: :update, identifier: 'ZNM')

      # Should create a normal UPDATE staged change
      batch = Processors::Base.current_batch
      assert_equal 1, batch.staged_changes.count
      assert_equal 'update', batch.staged_changes.first.operation
      assert_equal existing.id, batch.staged_changes.first.record_id
    end
  ensure
    Operator.where(icao_code: 'ZNM').delete_all
  end

  # ---------------------------------------------------------------------------
  # Progress broadcasting tests
  # ---------------------------------------------------------------------------

  test 'progress bar broadcasts to staged batch when in batch context' do
    batch = StagedBatch.create!(
      processor_type: 'TestProcessor',
      entity_type: 'Test',
      status: :processing,
      summary: { 'created' => 0, 'updated' => 0, 'unchanged' => 0 }
    )

    Processors::Base.current_batch = batch

    progress_bar = Processors::Base.create_progress_bar(100)

    # Verify that create_progress_bar sets processing_total on the batch
    batch.reload
    assert_equal 100, batch.processing_total

    # Increment enough times to trigger a broadcast (1% = 1 item out of 100)
    progress_bar.increment!
    batch.reload

    # broadcast_processing_progress_if_needed should have updated processing_progress
    assert_equal 1, batch.processing_progress
  ensure
    Processors::Base.current_batch = nil
    batch&.destroy
  end

  test 'create_progress_bar returns NullProgressBar when no batch context' do
    Processors::Base.current_batch = nil

    progress_bar = Processors::Base.create_progress_bar(100)

    assert_instance_of Processors::Base::NullProgressBar, progress_bar
  end

  test 'create_progress_bar sets processing_total on batch' do
    batch = StagedBatch.create!(
      processor_type: 'TestProcessor',
      entity_type: 'Test',
      status: :processing,
      summary: { 'created' => 0, 'updated' => 0, 'unchanged' => 0 }
    )

    Processors::Base.current_batch = batch

    Processors::Base.create_progress_bar(250)

    batch.reload
    assert_equal 250, batch.processing_total
  ensure
    Processors::Base.current_batch = nil
    batch&.destroy
  end
end
