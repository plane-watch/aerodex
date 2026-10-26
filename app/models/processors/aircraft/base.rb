# frozen_string_literal: true

module Processors
  module Aircraft
    # Base class for aircraft-related processors.
    #
    # Provides shared functionality for processing aircraft data from various
    # civil aviation authorities (CASA, CAANZ, etc.) including:
    # - Registration/ICAO hex code conversion
    # - Manufacturer name normalisation
    # - Aircraft model normalisation
    # - Operator name cleanup
    class Base < Processors::Base
      extend ManufacturerNormalisation

      CHARACTER_SET = ('A'..'Z').to_a + ('0'..'9').to_a

      AIRCRAFT_MODEL_PATTERNS = [
        [/^A(3[0-9]{3})-(\d{1,2})\d{2}/, 'A\1-\200'],
        [/F28 MK 0100/, '100'],
        [/F28MK0100/, '100'],
        [/F28 MK 070/, '70'],
        [/F28 MK 0070/, '70'],
        [/F28 MK070/, '70'],
        [/F28 MK0070/, '70'],
        [/F28MK070/, '70'],
        [/F28MK0070/, '70'],
        [/F27 MK 50/, '50'],
        [/MK/, 'Mk'],
        [/BAE 146 SERIES /, 'BAE 146-'],
        [/B.AE. 146 SERIES /, 'BAE 146-'],
        [/EMB-110P1/, 'EMB-110 P1'],
        [/EMB-135BJ/, 'ERJ-135 BJ Legacy'],
        [/EMB-135KL/, 'ERJ-135 KL'],
        [/EMB-145LR/, 'ERJ-145 LR'],
        [/ERJ 190-100lr/i, 'ERJ 190-100 LR'],
        [/EMB-500/, 'EMB-500 Phenom 100'],
        [/EMB-505/, 'EMB-500 Phenom 300'],
        [/AW /, 'AW'],
        [/AEROPRAKT/, 'A'],
        [/BETA/, 'Beta'],
        [/DA /, 'DA'],
        [/ATR72/, 'ATR 72'],
      ].freeze

      AIRCRAFT_MODEL_TO_FAMILY = [
        [/BD-500-1A10/, 'A220-200'],
        [/BD-500-1A11/, 'A220-300'],
        [/^A([234][0-9]{2})-(\d{1,2})\d{2}/, 'A\1-\200'],
        [/^B(7[0-9]{2})-(\d{1,2})\d{2}/, 'B\1-\200'],
        [/PC-(\d+).*/, 'PC-\1'],
        [%r{(.*)/,}, '\1'],
      ].freeze

      ICAO_MODEL_PATTERN = [
        [/^A-([234]\d{2,3})-/, 'A\1-'],         # Airbus A-3XX-XXX -> A3XX-XXX
        [/^A-([234]\d{2,3})(.*)?$/, 'A\1\2'],   # Airbus A-3XX -> A3XX
        [/^A-([234]00\w*)(-?)/, 'A\1\2'],       # Airbus A-300XX-XXX -> A300XX-XXX or A-300XX -> A300XX
        [/^C-212/, 'C212'],                     # Airbus/CASA C-212 -> C212
        [/^ACJ \(A-319\)/, 'ACJ-319'],          # Airbus ACJ (A3-319) -> ACJ-319
      ].freeze

      OPERATOR_REPLACEMENT_PATTERNS = [
        [/ PTY\.? LTD\.?\z/i, ''],
        [/ PTY\.? LIMITED/i, ''],
        [/ PROPRIETARY LIMITED$/, ''],
        [/ LIMITED$/i, ''],
        [/ \(?INC\.?\)?$/i, ''],
        [/ INCORPORATED$/i, ''],
        [/ PROPERTY TRUST/, ''],
        [/JETSTAR AIRWAYS/, 'Jetstar'],
        [/QANTAS AIRWAYS/, 'Qantas'],
        [/VIRGIN AUSTRALIA INTERNATIONAL AIRLINES/, 'Virgin Australia'],
        [/VIRGIN AUSTRALIA INTERNATIONAL AIRLINES PTY LTD/, 'Virgin Australia'],
        [/VIRGIN AUSTRALIA AIRLINES/, 'Virgin Australia'],
        [/^CAPITEQ$/, 'Airnorth (Capiteq Pty Ltd)'],
        [/^NANTAY$/, 'Maroomba Airlines (Nantay Pty Ltd)'],
        [/COMMONWEALTH OF AUSTRALIA (CADETS BRANCH - AIR FORCE)/, 'Australian Air Force Cadets'],
        [/COMMONWEALTH OF AUSTRALIA (DEPARTMENT OF DEFENCE)/, 'Defence Australia'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY RAAF RICHMOND FLYING CLUB/, 'RAAF Richmond Flying Club'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY RAAF RICHMOND GLIDING CLUB/, 'RAAF Richmond Gliding Club'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY ROYAL AUSTRALIAN AIR FORCE 100 SQUADRON/,
         'Royal Australian Air Force No. 100 Squadron'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY ROYAL AUSTRALIAN AIR FORCE/, 'Royal Australian Air Force'],
        [/ROYAL FLYING DOCTOR SERVICE OF AUSTRALIA \((.*)\)/, 'Royal Flying Doctor Service of Australia (\1)'],
        [/ROYAL FLYING DOCTOR SERVICE OF AUSTRALIA CENTRAL OPERATIONS/,
         'Royal Flying Doctor Service of Australia (Central Operations)'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY DEPARTMENT OF PLANNING AND ENVIRONMENT/,
         'Dept. of Planning and Environment (NSW)'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY NSW POLICE FORCE/, 'New South Wales Police Force'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY NSW RURAL FIRE SERVICE/, 'New South Wales Rural Fire Service'],
        [/State of South Australia Represented by Department for Environment and Water/,
         'Dept. for Environment and Water (SA)'],
        [/STATE OF SOUTH AUSTRALIA REPRESENTED BY SOUTH AUSTRALIA POLICE/, 'South Australia Police'],
        [/STATE OF WESTERN AUSTRALIA REPRESENTED BY DEPARTMENT OF THE PREMIER AND CABINET/,
         'Dept. of the Premier and Cabinet (WA)'],
        [/STATE OF WESTERN AUSTRALIA - REPRESENTED BY COMMISSIONER OF POLICE/, 'Western Australia Police Force'],
        [/STATE OF WESTERN AUSTRALIA/, 'Dept. of Biodiversity Conservation and Attractions (WA)'],
      ].freeze

      class << self
        def get_aircraft_manufacturer(manufacturer)
          normalised_name = normalise_manufacturer_name(manufacturer)

          manufacturer_obj = Rails.cache.fetch("aircraft_manufacturer_#{normalised_name}") do
            ::Manufacturer.find_by(name: normalised_name)
          end

          raise ActiveRecord::RecordNotFound unless manufacturer_obj

          manufacturer_obj.id
        end

        def get_aircraft_type(type_code)
          aircraft_type_obj = Rails.cache.fetch("aircraft_type_typecode_#{type_code}") do
            ::AircraftType.find_by(type_code: type_code)
          end

          raise ActiveRecord::RecordNotFound unless aircraft_type_obj

          aircraft_type_obj.id
        end

        def normalise_name(name)
          name
        end

        def normalise_model(input)
          model = input.dup
          # Ensure the model is a stripped string and hasn't been cast to another type
          model = model.to_s.strip

          AIRCRAFT_MODEL_TO_FAMILY.each { |pattern, replacement| model.gsub!(pattern, replacement) }
          model
        end

        # Normalises an operator name and finds or creates the corresponding Operator record.
        # Uses database lookups with retry logic to handle race conditions during parallel imports.
        #
        # @param input [String] The raw operator name from the source data
        # @param country [String] The country name
        # @return [Operator] The found or created operator
        # @raise [ActiveRecord::RecordNotFound] If the country is not found
        def normalise_and_find_operator(input, country:)
          name = normalise_operator_name(input)

          # Look up the country first (cached)
          country_record = lookup_country(country)
          raise ActiveRecord::RecordNotFound, "Country not found: #{country}" if country_record.nil?

          find_or_create_operator(name, country_record)
        end

        # Normalises an operator name by applying replacement patterns and title casing.
        #
        # @param input [String] The raw operator name
        # @return [String] The normalised name
        def normalise_operator_name(input)
          name = input.to_s.dup
          OPERATOR_REPLACEMENT_PATTERNS.each { |pattern, replacement| name.gsub!(pattern, replacement) }
          name.strip.titleize
        end

        private

        # Looks up a country by name, with caching.
        #
        # @param country_name [String] The country name
        # @return [Country, nil] The country record or nil if not found
        def lookup_country(country_name)
          @country_cache ||= {}
          @country_cache[country_name] ||= ::Country.find_by(name: country_name)
        end

        # Finds an existing operator or creates a new one.
        # Uses database lookup (not search index) for reliability.
        # Handles race conditions by retrying the find if insert fails.
        #
        # @param name [String] The normalised operator name
        # @param country [Country] The country record
        # @return [Operator] The found or created operator
        def find_or_create_operator(name, country)
          # First, try exact match on name and country (case-insensitive)
          operator = find_operator_by_name_and_country(name, country)
          return operator if operator

          # Not found - create new operator with validation enabled
          operator = ::Operator.new(name: name, country: country)

          begin
            operator.save!
            Rails.logger.debug "Created new operator: #{name} (#{country.name})"
            operator
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
            # Race condition - another process created it. Find and return it.
            operator = find_operator_by_name_and_country(name, country)

            if operator.nil?
              # Still not found - this is an actual error, not a race condition
              Rails.logger.error "Failed to create operator '#{name}': #{e.message}"
              raise
            end

            operator
          end
        end

        # Finds an operator by name and country (case-insensitive).
        #
        # @param name [String] The operator name
        # @param country [Country] The country record
        # @return [Operator, nil] The operator or nil if not found
        def find_operator_by_name_and_country(name, country)
          ::Operator.find_by(
            'LOWER(name) = LOWER(?) AND country_id = ?',
            name,
            country.id
          )
        end
      end
    end
  end
end
