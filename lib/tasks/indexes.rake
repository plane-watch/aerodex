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
end
