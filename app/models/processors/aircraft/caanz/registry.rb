# frozen_string_literal: true

module Processors
  module Aircraft
    module CAANZ
      # Processor for importing New Zealand aircraft registry data from CAANZ.
      #
      # This processor scrapes aircraft details from the CAANZ website and imports
      # them into the CAANZAircraftSource table. The data is then combined with
      # other sources using Processors::Aircraft::Aircraft#combine_sources.
      #
      # @example Looking up a single aircraft
      #   Processors::Aircraft::CAANZ::Registry.search('ZK-ABC')
      #
      # @example Importing a single aircraft to source table
      #   Processors::Aircraft::CAANZ::Registry.import('ZK-ABC')
      class Registry < Processors::Aircraft::Base
        @transform_data = {
          'Reg Mark' => {
            field: :registration
          },
          'Man. Model' => {
            function: ->(model) { extract_type_code(model) },
            field: :type_code
          },
          'Name and Address' => {
            function: lambda { |v|
              normalise_name(v.gsub(/^(.*)\r\n.*$/, '\\1'))
            },
            field: :operator_name
          },
          'SerialNo' => {
            field: :serial_number
          },
          'Mode S Code Country/Aircraft' => {
            field: :icao,
            function: ->(v) { extract_icao(v) }
          }
        }

        class << self
          # Searches for an aircraft on the CAANZ website and returns raw data.
          #
          # @param registration [String] The registration (e.g., 'ZK-ABC')
          # @return [Hash, false] The raw data hash or false if not found
          def search(registration)
            search_param = registration.gsub(/^ZK-/, '')
            data = {}
            url = "https://caanz.cwp.govt.nz/aircraft/aircraft-registration/aircraft-register-search/ShowDetails/#{search_param}"

            response = Rails.cache.fetch("Processors::Aircraft::CAANZ::Registry#search/#{search_param}") do
              Excon.get(url,
                        headers: {
                          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:122.0) Gecko/20100101 Firefox/122.0',
                          'Referer' => "https://caanz.cwp.govt.nz/aircraft/aircraft-registration/aircraft-register-search/querymark?Mark=#{search_param}"
                        }, debug: true, omit_default_port: true)
            end

            return false unless response.status == 200

            doc = Nokogiri::HTML(response.body)
            rows = doc.css('.row-header, .row-detail').collect(&:text)
            while rows.any?
              key, value = rows.shift(2)
              transformed_data = transform_row(key, value)
              next if transformed_data.nil?

              data[transformed_data[:key].to_sym] = transformed_data[:value]
            end

            data
          end

          # Imports a single aircraft from CAANZ into the source table.
          #
          # @param registration [String] The registration (e.g., 'ZK-ABC')
          # @return [Hash] Result with :success or :error key
          def import(registration)
            data = search(registration)
            return { error: { registration: registration, errors: ['Aircraft not found on CAANZ'] } } unless data

            icao = data[:icao]
            return { error: { registration: registration, errors: ['Could not extract ICAO code'] } } if icao.blank?

            source = Source::Aircraft::CAANZAircraftSource.find_or_initialize_by(icao: icao)
            source.assign_attributes(
              registration: data[:registration] || registration,
              icao: icao,
              serial_number: data[:serial_number],
              type_code: data[:type_code],
              operator_name: data[:operator_name],
              registration_country_code: 'NZ',
              import_date: Time.current
            )

            if source.save
              { success: registration }
            else
              { error: { registration: registration, errors: source.errors.full_messages } }
            end
          end

          # Bulk imports multiple aircraft from CAANZ.
          #
          # @param registrations [Array<String>] List of registrations to import
          # @return [Hash] Result with :success and :errors arrays
          def bulk_import(registrations)
            success = []
            errors = []

            progress_bar = create_progress_bar(registrations.count)

            Source::Aircraft::CAANZAircraftSource.transaction do
              registrations.each do |registration|
                result = import(registration)

                if result[:success]
                  success << result[:success]
                else
                  errors << result[:error]
                end

                progress_bar.increment!
              end
            end

            # Create an import report
            new_import_report(errors, registrations.count)

            { success: success, errors: errors }
          end

          def transform_row(key, value)
            key = key&.strip&.gsub(/:$/, '')
            value = value&.strip

            return nil if key.nil? || value.nil?
            return nil if @transform_data[key].nil?

            {
              key: @transform_data[key][:field] || key,
              value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
            }
          end

          def extract_icao(input)
            input.split(/\n/).last.split(/\s+/).last
          end

          # Extracts the ICAO type code from the manufacturer/model string.
          #
          # @param input [String] The manufacturer and model string (e.g., 'Cessna 172')
          # @return [String, nil] The type code if found
          def extract_type_code(input)
            tokens = input.split.map.with_index(1) { |_, i| input.split.first(i).join(' ') }
            manufacturer = ::Manufacturer.where(name: tokens).order('length(name) DESC').first
            return nil if manufacturer.nil?

            aircraft_model = input.gsub(/^#{manufacturer.name} /, '')
            aircraft_type = ::AircraftType.joins(:manufacturer)
                                          .find_by(name: aircraft_model, manufacturer: { name: manufacturer.name })
            aircraft_type&.type_code
          end
        end
      end
    end
  end
end