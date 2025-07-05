# frozen_string_literal: true

module Processors
  module Aircraft
    module CASA
      class Csv < Processors::Aircraft::CASA::Registry
        @transform_data = {
          'model' => {
            function: ->(model) { normalise_model(model) },
            field: :model,
          },
          'icaotypedesig' => {
            function: ->(v) { get_aircraft_type(v) },
            field: :aircraft_type_id,
          },
          'datefirstreg' => {
            function: ->(v) { Date.parse(v) },
            field: :registration_date,
          },
          'serial' => {
            field: :serial_number
          },
          'regholdname' => {
            function: ->(v) { normalise_name(v) },
            field: :owner,
          },
          'regopname' => {
            function: ->(v) { normalise_and_find_operator(v, country: 'Australia') },
            field: :operator,
          },
          'engnum' => {
            function: ->(v) { v.to_i },
            field: :engine_count,
          },
          'engmodel' => {
            field: :engine_model,
          },
        }

        class << self
          def bulk_import(file_path)
            missing_types = []
            errors = []
            success = []
            CSV.foreach(file_path, headers: true, header_converters: :symbol, converters: :all).each do |row|
              data = {
                registration: "VH-#{row[:mark]}",
                icao: reg_to_hex("VH-#{row[:mark]}"),
              }
              row.each do |k, v|
                begin
                  transformed_data = transform_row(k.to_s, v)
                  next if transformed_data.nil?
                rescue ActiveRecord::RecordNotFound
                  errors << { registration: data[:registration], errors: "Aircraft type not found #{row[:icaotypedesig]}" }
                  missing_types << row[:icaotypedesig] unless missing_types.include?(row[:icaotypedesig])
                  next
                end
                data[transformed_data[:key]] = transformed_data[:value]
              end

              obj = Aircraft.find_or_initialize_by(
                registration: data[:registration],
                serial_number: data[:serial_number],
                aircraft_type_id: data[:aircraft_type_id]
              )

              obj.assign_attributes(data)
              begin
                obj.save!
                success << "VH-#{row[:mark]}"
              rescue ActiveRecord::RecordInvalid
                errors << { registration: data[:registration], errors: obj.errors.full_messages }
              end
            end

            { success: success, errors: errors, missing_types: missing_types }
          end

          def transform_row(a, b)
            key = a.to_s
            value = b
            value.strip! if value.is_a?(String)

            return nil if key.nil? || value.nil?

            if @transform_data[key].nil?
              return nil
            end

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