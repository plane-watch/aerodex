# frozen_string_literal: true

namespace :indexes do
  # Finds all models that have Meilisearch configured
  def searchable_models
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.select do |model|
      model.respond_to?(:meilisearch_settings) && model.meilisearch_settings.present?
    end.sort_by(&:name)
  end

  desc 'Reindex all Meilisearch indexes (clear and rebuild)'
  task reindex_all: :environment do
    searchable_models.each do |model|
      puts "Reindexing #{model.name}..."
      model.clear_index!
      model.reindex!
      count = model.index.stats['numberOfDocuments']
      puts "  -> #{count} documents indexed"
    end

    puts 'Done.'
  end

  desc 'Reindex a specific model (e.g. rake indexes:reindex[Aircraft])'
  task :reindex, [:model_name] => :environment do |_t, args|
    model_name = args[:model_name]

    if model_name.blank?
      puts 'Usage: rake indexes:reindex[ModelName]'
      puts "Available models: #{searchable_models.map(&:name).join(', ')}"
      exit 1
    end

    model = model_name.safe_constantize
    if model.nil? || !model.respond_to?(:meilisearch_settings)
      puts "Unknown or non-searchable model: #{model_name}"
      exit 1
    end

    puts "Reindexing #{model.name}..."
    model.clear_index!
    model.reindex!
    count = model.index.stats['numberOfDocuments']
    puts "  -> #{count} documents indexed"
    puts 'Done.'
  end

  desc 'Show index statistics for all models'
  task stats: :environment do
    puts 'Index Statistics:'
    puts '-' * 50

    searchable_models.each do |model|
      # Use index stats for accurate document count (not capped like search results)
      stats = model.index.stats
      count = stats['numberOfDocuments']
      db_count = model.count
      status = count == db_count ? '✓' : '!'
      puts "#{model.name.ljust(25)} #{count.to_s.rjust(8)} indexed / #{db_count.to_s.rjust(8)} in DB  #{status}"
    rescue StandardError => e
      puts "#{model.name.ljust(25)} Error: #{e.message}"
    end
  end

  desc 'List all searchable models'
  task list: :environment do
    puts 'Searchable models:'
    searchable_models.each do |model|
      fields = model.meilisearch_settings.get_setting(:filterableAttributes) || []
      puts "  #{model.name}: #{fields.join(', ')}"
    end
  end

  desc 'Reset all counter caches (use after bulk imports)'
  task reset_counters: :environment do
    puts 'Resetting counter caches...'
    puts

    # Aircraft -> Operator (aircraft_count)
    puts 'Operator.aircraft_count...'
    Operator.connection.execute(<<~SQL.squish)
      UPDATE operators
      SET aircraft_count = (
        SELECT COUNT(*)
        FROM aircraft
        WHERE aircraft.operator_id = operators.id
      )
    SQL

    # Aircraft -> AircraftType (aircraft_count)
    puts 'AircraftType.aircraft_count...'
    AircraftType.connection.execute(<<~SQL.squish)
      UPDATE aircraft_types
      SET aircraft_count = (
        SELECT COUNT(*)
        FROM aircraft
        WHERE aircraft.aircraft_type_id = aircraft_types.id
      )
    SQL

    # AircraftType -> Manufacturer (aircraft_types_count)
    puts 'Manufacturer.aircraft_types_count...'
    Manufacturer.connection.execute(<<~SQL.squish)
      UPDATE manufacturers
      SET aircraft_types_count = (
        SELECT COUNT(*)
        FROM aircraft_types
        WHERE aircraft_types.manufacturer_id = manufacturers.id
      )
    SQL

    # Manufacturer.aircraft_count (sum of aircraft_types' aircraft_count)
    puts 'Manufacturer.aircraft_count...'
    Manufacturer.connection.execute(<<~SQL.squish)
      UPDATE manufacturers
      SET aircraft_count = (
        SELECT COALESCE(SUM(aircraft_types.aircraft_count), 0)
        FROM aircraft_types
        WHERE aircraft_types.manufacturer_id = manufacturers.id
      )
    SQL

    # AirportRunway -> Airport (airport_runways_count)
    puts 'Airport.airport_runways_count...'
    Airport.connection.execute(<<~SQL.squish)
      UPDATE airports
      SET airport_runways_count = (
        SELECT COUNT(*)
        FROM airport_runways
        WHERE airport_runways.airport_id = airports.id
      )
    SQL

    # Airport -> Country (airports_count)
    puts 'Country.airports_count...'
    Country.connection.execute(<<~SQL.squish)
      UPDATE countries
      SET airports_count = (
        SELECT COUNT(*)
        FROM airports
        WHERE airports.country_id = countries.id
      )
    SQL

    # Operator -> Country (operators_count)
    puts 'Country.operators_count...'
    Country.connection.execute(<<~SQL.squish)
      UPDATE countries
      SET operators_count = (
        SELECT COUNT(*)
        FROM operators
        WHERE operators.country_id = countries.id
      )
    SQL

    puts
    puts 'Done.'
  end
end
