# frozen_string_literal: true

namespace :processors do
  desc 'Run a processor (enqueues background job)'
  task :run, [:entity_type] => :environment do |_t, args|
    entity_type = args[:entity_type]
    abort 'Usage: rake processors:run[EntityType] (e.g., processors:run[Aircraft])' if entity_type.blank?

    processor_class = "Processors::#{entity_type}::#{entity_type}"

    # Verify the processor exists
    begin
      processor_class.constantize
    rescue NameError
      abort "Unknown processor: #{processor_class}"
    end

    job = ProcessorJob.perform_later(processor_class)
    puts "Enqueued #{processor_class}"
    puts "Job ID: #{job.job_id}"
  end

  desc 'Run a processor synchronously (for debugging)'
  task :run_sync, [:entity_type] => :environment do |_t, args|
    entity_type = args[:entity_type]
    abort 'Usage: rake processors:run_sync[EntityType]' if entity_type.blank?

    processor_class = "Processors::#{entity_type}::#{entity_type}"

    # Verify the processor exists
    begin
      processor_class.constantize
    rescue NameError
      abort "Unknown processor: #{processor_class}"
    end

    puts "Running #{processor_class}..."
    batch = ProcessorJob.perform_now(processor_class)

    puts 'Completed.'
    puts "Batch ID: #{batch.id}"
    puts "Status: #{batch.status}"
    puts "Summary: #{batch.summary}"
  end

  desc 'Run all processors synchronously'
  task run_all_sync: :environment do
    processors = Dir[Rails.root.join('app/models/processors/**/')].filter_map do |dir|
      entity = File.basename(dir)
      next if ['.', 'processors'].include?(entity)

      processor_file = File.join(dir, "#{entity}.rb")
      entity.camelize if File.exist?(processor_file)
    end.sort

    if processors.empty?
      puts 'No processors found.'
      next
    end

    puts "Running #{processors.count} processors..."
    processors.each do |entity_type|
      processor_class = "Processors::#{entity_type}::#{entity_type}"

      begin
        processor_class.constantize
      rescue NameError
        puts "  Skipping unknown processor: #{processor_class}"
        next
      end

      puts "  Running #{processor_class}..."
      batch = ProcessorJob.perform_now(processor_class)
      puts "  Completed: #{batch.status} - #{batch.summary}"
    end

    puts 'All processors complete.'
  end

  desc 'List all available processors'
  task list: :environment do
    processors = Dir[Rails.root.join('app/models/processors/**/')].map do |dir|
      entity = File.basename(dir)
      next if ['.', 'processors'].include?(entity)

      processor_file = File.join(dir, "#{entity}.rb")
      entity.camelize if File.exist?(processor_file)
    end.compact

    puts 'Available processors:'
    processors.each { |p| puts "  - #{p}" }
  end
end
