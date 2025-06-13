# frozen_string_literal: true

module Processors
  module Aircraft
    module CASA
      class Registry < Processors::Aircraft::Base
        CHARACTER_SET = ('A'..'Z').to_a + ('0'..'9').to_a

        @transform_data = {
          'Aircraft model' => {
            function: ->(model) { normalise_model(model) },
            field: :model,
          },
          'ICAO type designator' => {
            function: ->(v) { get_aircraft_type(v) },
            field: :aircraft_type_id,
          },
          'Date first registered' => {
            function: ->(v) { Date.parse(v) },
            field: :registration_date,
          },
          'Serial' => {
            field: :serial_number,
            function: ->(v) { v.to_s },
          },
          'Registration holder' => {
            function: ->(v) { normalise_name(v) },
            field: :owner,
          },
          'Registered operator' => {
            function: ->(v) { normalise_and_find_operator(v, country: 'Australia') },
            field: :operator,
          },
          'Number of engines' => {
            function: ->(v) { v.to_i },
            field: :engine_count,
          },
          'Engine model' => {
            field: :engine_model,
          },
        }

        class << self
          def transform_row(a, b)
            key = a&.text&.strip&.gsub(/:$/, '')
            value = b&.text&.strip

            return nil if key.nil? || value.nil?
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
            registration[3..-1].chars.each_with_index do |char, index|
              dec += CHARACTER_SET.index(char) * factors[index]
            end

            # convert the decimal value to hex, 0 padded to 4 characters
            sprintf("7C%04X", dec)
          end
        end
      end
    end
  end
end