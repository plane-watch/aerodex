# frozen_string_literal: true

namespace :sources do
  desc 'Dump all source tables to JSON files in db/sources/'
  task dump: :environment do
    dump_dir = Rails.root.join('db', 'sources')
    FileUtils.mkdir_p(dump_dir)

    source_classes = discover_source_classes
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')

    puts "Dumping #{source_classes.count} source types to #{dump_dir}/"

    source_classes.each do |klass|
      dump_source_class(klass, dump_dir, timestamp)
    end

    puts "\nDump complete. Files written to #{dump_dir}/"
  end

  desc 'Dump a specific source type (e.g., rake sources:dump_type[VRSDataOperatorSource])'
  task :dump_type, [:source_type] => :environment do |_t, args|
    source_type = args[:source_type]
    raise ArgumentError, 'Source type is required' if source_type.blank?

    dump_dir = Rails.root.join('db', 'sources')
    FileUtils.mkdir_p(dump_dir)

    klass = find_source_class(source_type)
    raise ArgumentError, "Unknown source type: #{source_type}" unless klass

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    dump_source_class(klass, dump_dir, timestamp)

    puts "\nDump complete."
  end

  desc 'Import sources from JSON files in db/sources/'
  task import: :environment do
    import_dir = Rails.root.join('db', 'sources')

    unless Dir.exist?(import_dir)
      puts "Import directory not found: #{import_dir}"
      exit 1
    end

    json_files = Dir.glob(import_dir.join('*.json')).sort
    if json_files.empty?
      puts 'No JSON files found in import directory'
      exit 1
    end

    puts "Found #{json_files.count} source files to import"
    puts ''

    json_files.each do |file_path|
      import_source_file(file_path)
    end

    puts "\nImport complete."
  end

  desc 'Import a specific source file (e.g., rake sources:import_file[db/sources/vrs_data_operator_sources.json])'
  task :import_file, [:file_path] => :environment do |_t, args|
    file_path = args[:file_path]
    raise ArgumentError, 'File path is required' if file_path.blank?

    full_path = Rails.root.join(file_path)
    raise ArgumentError, "File not found: #{full_path}" unless File.exist?(full_path)

    import_source_file(full_path)

    puts "\nImport complete."
  end

  desc 'List available source types and their record counts'
  task list: :environment do
    source_classes = discover_source_classes

    puts 'Available source types:'
    puts ''

    total = 0
    source_classes.each do |klass|
      count = klass.count
      total += count
      excluded = klass.excluded.count
      excluded_str = excluded.positive? ? " (#{excluded} excluded)" : ''
      puts "  #{klass.name.demodulize.ljust(45)} #{count.to_s.rjust(8)} records#{excluded_str}"
    end

    puts ''
    puts "Total: #{total} source records"
  end

  desc 'Clear all source tables (use with caution!)'
  task clear: :environment do
    puts 'This will DELETE all source records. Are you sure? (type YES to confirm)'
    confirmation = $stdin.gets.chomp

    unless confirmation == 'YES'
      puts 'Aborted.'
      exit 1
    end

    source_classes = discover_source_classes
    source_classes.each do |klass|
      count = klass.count
      klass.delete_all
      puts "Deleted #{count} records from #{klass.table_name}"
    end

    puts 'All source tables cleared.'
  end

  # ===========================================================================
  # Helper methods
  # ===========================================================================

  # Discovers all source model classes by scanning the source directory.
  #
  # @return [Array<Class>] All source model classes
  def discover_source_classes
    source_dir = Rails.root.join('app', 'models', 'source')
    source_classes = []

    Dir.glob(source_dir.join('**', '*_source.rb')).each do |file|
      # Extract class name from file path
      # e.g., app/models/source/operator/vrs_data_operator_source.rb
      #    => Source::Operator::VRSDataOperatorSource
      relative_path = file.sub("#{source_dir}/", '').sub('.rb', '')
      class_name = "Source::#{relative_path.camelize}"

      begin
        klass = class_name.constantize
        # Only include concrete classes (not base classes)
        source_classes << klass if klass < ApplicationRecord && !klass.abstract_class?
      rescue NameError
        # Skip if class doesn't exist
      end
    end

    source_classes.sort_by(&:name)
  end

  # Finds a source class by its short name.
  #
  # @param source_type [String] The source type name (e.g., 'VRSDataOperatorSource')
  # @return [Class, nil] The source class or nil if not found
  def find_source_class(source_type)
    discover_source_classes.find do |klass|
      klass.name.demodulize == source_type || klass.name == source_type
    end
  end

  # Dumps a source class to a JSON file.
  #
  # @param klass [Class] The source class to dump
  # @param dump_dir [Pathname] The directory to write to
  # @param timestamp [String] Timestamp for the filename
  def dump_source_class(klass, dump_dir, timestamp)
    count = klass.count
    return puts "  #{klass.name.demodulize}: 0 records (skipped)" if count.zero?

    # Use the table name as the base filename (without timestamp for easier import)
    filename = "#{klass.table_name.singularize}_#{klass.name.demodulize.underscore}.json"
    file_path = dump_dir.join(filename)

    print "  #{klass.name.demodulize}: #{count} records..."

    # Stream records to file to handle large datasets
    File.open(file_path, 'w') do |file|
      file.puts '{'
      file.puts "  \"source_type\": \"#{klass.name}\","
      file.puts "  \"exported_at\": \"#{Time.current.iso8601}\","
      file.puts "  \"count\": #{count},"
      file.puts '  "records": ['

      first = true
      klass.find_each do |record|
        file.puts ',' unless first
        first = false

        # Export all attributes except id (will be regenerated on import)
        attrs = record.attributes.except('id')
        file.print "    #{attrs.to_json}"
      end

      file.puts ''
      file.puts '  ]'
      file.puts '}'
    end

    file_size = File.size(file_path)
    puts " #{human_file_size(file_size)} -> #{filename}"
  end

  # Imports sources from a JSON file.
  #
  # @param file_path [String, Pathname] The file to import
  def import_source_file(file_path)
    filename = File.basename(file_path)
    file_size = File.size(file_path)

    print "Importing #{filename} (#{human_file_size(file_size)})..."

    # Parse the JSON file
    data = JSON.parse(File.read(file_path))
    source_type = data['source_type']
    records = data['records']

    unless source_type && records
      puts ' ERROR: Invalid file format'
      return
    end

    # Find the source class
    begin
      klass = source_type.constantize
    rescue NameError
      puts " ERROR: Unknown source type #{source_type}"
      return
    end

    # Determine the natural key for this source type
    natural_key = natural_key_for(klass)

    # Build a set of existing records for deduplication
    existing_keys = Set.new
    if natural_key
      klass.pluck(*natural_key).each do |key_values|
        # Handle single vs multi-column keys
        key = key_values.is_a?(Array) ? key_values : [key_values]
        existing_keys << key
      end
    end

    # Import in batches, skipping duplicates
    batch_size = 1000
    imported = 0
    skipped = 0

    records.each_slice(batch_size) do |batch|
      import_records = []

      batch.each do |attrs|
        # Check for duplicates based on natural key
        if natural_key
          key_values = natural_key.map { |col| attrs[col.to_s] }
          if existing_keys.include?(key_values)
            skipped += 1
            next
          end
          existing_keys << key_values
        end

        # Ensure timestamps are present
        attrs['created_at'] ||= Time.current
        attrs['updated_at'] ||= Time.current
        import_records << attrs
      end

      next if import_records.empty?

      # Insert the batch
      klass.insert_all(import_records)
      imported += import_records.size
    end

    skipped_str = skipped.positive? ? " (#{skipped} duplicates skipped)" : ''
    puts " #{imported} records imported#{skipped_str}"
  end

  # Determines the natural key (unique identifier columns) for a source class.
  # This is used for deduplication during import.
  #
  # @param klass [Class] The source class
  # @return [Array<Symbol>, nil] The natural key columns
  def natural_key_for(klass)
    # First check for a unique database index
    table_name = klass.table_name
    indexes = ActiveRecord::Base.connection.indexes(table_name)
    unique_index = indexes.find(&:unique)
    return unique_index.columns.map(&:to_sym) if unique_index

    # Fall back to known natural keys by source type pattern
    class_name = klass.name.demodulize

    case class_name
    when /OperatorSource$/
      %i[type icao_code]
    when /AircraftSource$/
      %i[type icao]
    when /AircraftTypeSource$/
      %i[type type_code name]
    when /AirportSource$/
      %i[type icao_code]
    when /RunwaySource$/
      %i[type airport_ident le_ident]
    when /CountrySource$/
      %i[type iso_2char_code]
    when /ManufacturerSource$/
      %i[type icao_code]
    else
      # No natural key - will insert all records
      nil
    end
  end

  # Formats a file size for display.
  #
  # @param bytes [Integer] The file size in bytes
  # @return [String] Human-readable file size
  def human_file_size(bytes)
    units = %w[B KB MB GB]
    unit_index = 0

    size = bytes.to_f
    while size >= 1024 && unit_index < units.size - 1
      size /= 1024
      unit_index += 1
    end

    format('%.1f %s', size, units[unit_index])
  end
end