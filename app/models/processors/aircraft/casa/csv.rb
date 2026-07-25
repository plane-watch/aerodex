# frozen_string_literal: true

module Processors
  module Aircraft
    module CASA
      # Processor for importing Australian aircraft registry data from CASA CSV files.
      #
      # This processor reads CSV exports from CASA and imports them into the
      # CASAAircraftSource table. The data is then combined with other sources
      # using Processors::Aircraft::Aircraft#combine_sources.
      #
      # @example Importing from a CSV file
      #   Processors::Aircraft::CASA::CSV.bulk_import('/path/to/casa_export.csv')
      class CSV < Processors::Aircraft::CASA::Registry
        CHARACTER_SET = ('A'..'Z').to_a + ('0'..'9').to_a

        # Field mappings for CSV columns to source table fields
        # Note: CSV converters may cast values to Integer/Date, so functions must handle multiple types
        # Every entry in this table is a lambda, including those whose body is a
        # single method call. Rewriting only those few as symbol-to-proc would make
        # them read differently from their neighbours for no gain, and the table is
        # easier to scan when each transform has the same shape.
        # rubocop:disable Style/SymbolProc
        @transform_data = {
          'model' => {
            function: ->(model) { normalise_model(model.to_s) },
            field: :model
          },
          'icaotypedesig' => {
            function: ->(v) { v.to_s.strip },
            field: :type_code
          },
          'datefirstreg' => {
            function: ->(v) { v.is_a?(Date) ? v : Date.parse(v.to_s) },
            field: :registration_date
          },
          'serial' => {
            function: ->(v) { v.to_s },
            field: :serial_number
          },
          'regholdname' => {
            function: ->(v) { normalise_name(v.to_s) },
            field: :owner
          },
          'regopname' => {
            function: ->(v) { normalise_name(v.to_s) },
            field: :operator_name
          },
          'engnum' => {
            function: ->(v) { v.to_i },
            field: :engine_count
          },
          'engmodel' => {
            function: ->(v) { v.to_s },
            field: :engine_model
          }
        }
        # rubocop:enable Style/SymbolProc

        class << self
          # Imports aircraft data from a CASA CSV file into the source table.
          #
          # @param file_path [String] Path to the CSV file
          # @return [Hash] Result with :success, :errors, and :missing_types arrays
          def bulk_import(file_path)
            require 'csv'

            errors = []
            success = []
            records_processed = 0

            progress_bar = create_progress_bar(count_csv_rows(file_path))

            Source::Aircraft::CASAAircraftSource.transaction do
              ::CSV.foreach(file_path, headers: true, header_converters: :symbol, converters: :all) do |row|
                records_processed += 1
                result = import_row(row)

                if result[:error]
                  errors << result[:error]
                else
                  success << result[:registration]
                end

                progress_bar.increment!
              end
            end

            # Create an import report
            new_import_report(errors, records_processed)

            { success: success, errors: errors }
          end

          private

          # Imports a single CSV row into the source table.
          #
          # @param row [CSV::Row] The CSV row to import
          # @return [Hash] Result with :registration or :error key
          def import_row(row)
            registration = "VH-#{row[:mark]}"
            icao = reg_to_hex(registration)

            return { error: { registration: registration, errors: ['Invalid registration format'] } } unless icao

            data = {
              registration: registration,
              icao: icao,
              registration_country_code: 'AU',
              import_date: Time.current
            }

            # Transform each field from the CSV
            row.each do |key, value|
              next if value.nil?

              transformed = transform_row(key.to_s, value)
              next if transformed.nil?

              data[transformed[:key]] = transformed[:value]
            end

            # Find or initialise the source record
            source = Source::Aircraft::CASAAircraftSource.find_or_initialize_by(icao: icao)
            source.assign_attributes(data)

            if source.save
              { registration: registration }
            else
              { error: { registration: registration, errors: source.errors.full_messages } }
            end
          end

          # Counts the number of rows in a CSV file (excluding header).
          #
          # @param file_path [String] Path to the CSV file
          # @return [Integer] The row count
          def count_csv_rows(file_path)
            File.foreach(file_path).count - 1
          end

          def transform_row(key, value)
            key = key.to_s
            value = value.to_s.strip if value.is_a?(String)

            return nil if key.nil? || value.nil?
            return nil if value.respond_to?(:empty?) && value.empty?
            return nil if @transform_data[key].nil?

            {
              key: @transform_data[key][:field] || key,
              value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
            }
          end

          def hex_to_reg(hex_code)
            # Remove the 7C prefix
            hex_code.sub!(/^7c/i, '')
            # Return false if the hex code is invalid
            return false if hex_code =~ /^[cf]/i

            # Convert the hex code to an integer
            hex_as_int = hex_code.to_i(16)

            # Define the integer factors for each character
            # The character set is 36 bits, so define the
            # factors as 36^3, 36^2, 36^1
            factors = [1296, 36, 1]

            # Define an array to store the characters
            chars = []

            factors.each do |factor|
              # If the hex code is greater than the factor
              # then divide the hex code by the factor and
              # store the remainder
              # Otherwise, set the index to 0
              if hex_as_int >= factor
                index = hex_as_int / factor
                hex_as_int -= (factor * index)
              else
                index = 0
              end

              # the resulting amount is the index of the
              # character in the character set
              # so, add the character to the array
              chars << CHARACTER_SET[index]
            end

            # return the complete registration
            "VH-#{chars.join('')}"
          end

          def reg_to_hex(registration)
            return false unless registration =~ /^VH-[A-Z0-9]{3}$/

            # Start with 0!
            dec = 0

            # Define the integer factors for each character
            # The character set is 36 bits, so define the
            # factors as 36^3, 36^2, 36^1
            factors = [1296, 36, 1]

            # step through each character in the registration
            # and add the value of the character to the
            # decimal value, multiplied by the factor
            registration[3..].chars.each_with_index do |char, index|
              dec += CHARACTER_SET.index(char) * factors[index]
            end

            # convert the decimal value to hex, 0 padded to 4 characters
            format('7C%04X', dec)
          end
        end
      end
    end
  end
end
