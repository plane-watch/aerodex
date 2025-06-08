# frozen_string_literal: true

# Parent class for all aircraft registry processors
# This class contains all the common methods and attributes
# for all aircraft registry processors, as well as the constants used
# for translating/normalising data.

module Processor
  module Aircraft
    class AircraftProcessor < Processor::ProcessorBase
      MANUFACTURER_REPLACEMENT_PATTERNS = [
        [/The Boeing Company/i, 'Boeing'],
        [/Airbus Industrie/i, 'Airbus'],
        [/Cessna Aircraft Company/i, 'Cessna'],
        [/Piper Aircraft.*$/i, 'Piper'],
        [/The New Piper.*$/i, 'Piper'],
        [/Beech.*$/i, 'Beechcraft'],
        [/Pilatus Aircraft Ltd.*/i, 'Pilatus'],
        [/Fokker.*$/i, 'Fokker'],
        [/Atr - Gie Avions.*$/i, 'ATR'],
        [/Fairchild.*$/i, 'Fairchild'],
        [/S.A.A.B..*$/i, 'SAAB'],
        [/SAAB.*$/i, 'SAAB'],
        [/North American Aviation Inc/i, 'North American Aviation'],
        [/Robinson Helicopter Co/i, 'Robinson'],
        [/Embraer.*$/i, 'Embraer'],
        [/Costruzioni Aeronautiche Tecnam.*$/i, 'Tecnam'],
        [/Tecnam.*$/i, 'Tecnam'],
        [/Commonwealth Aircraft Corporation.*$/i, 'CAC'],
        [/British Aerospace.*$/i, 'British Aerospace'],
        [/Partenavia Costruzioni Aeronautiche.*$/i, 'Partenavia'],
        [/Diamond Aircraft.*$/i, 'Diamond'],
        [/de Havilland.*$/i, 'de Havilland'],
        [/GippsAero Pty Ltd/i, 'GippsAero'],
        [/Gippsland Aeronautics Pty Ltd/i, 'GippsAero'],
        [/S.O.C.A.T.A.*$/i, 'SOCATA'],
        [/Dassault.*$/i, 'Dassault'],
        [/Mooney Aircraft Corp/i, 'Mooney'],
        [/Textron Aviation.*$/i, 'Textron Aviation'],
        [/American Champion.*$/i, 'American Champion'],
        [/Cirrus Design Corporation.*$/i, 'Cirrus'],
        [/Airbus Helicopters.*$/i, 'Airbus Helicopters'],
        [/Aerospatiale.*$/i, 'Aerospatiale'],
        [/Eurocopter.*$/i, 'Eurocopter'],
        [/Bell Helicopter Co/i, 'Bell'],
        [/Bell Helicopter Textron.*$/i, 'Bell Textron'],
        [/Bell Textron.*$/i, 'Bell Textron'],
        [/Costruzioni Aeronautiche Giovanni Agusta/i, 'Agusta'],
        [/Agusta S.*$/i, 'Agusta'],
        [/Agusta Aerospace.*$/i, 'Agusta'],
        [/Agusta, S.*$/i, 'Agusta'],
        [/Agustawestland.*$/i, 'AgustaWestland'],
        [/Leonardo S.P.A.*$/i, 'Leonardo'],
        [/Finmeccanica S.P.A.*$/i, 'Leonardo'],
        [/Sikorsky Aircraft.*$/i, 'Sikorsky'],
        [/Messerschmitt-Bolkow-Blohm GMBH/i, 'MBB'],
      ].freeze

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
        [/(.*)\/,/, '\1'],
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
        [/VIRGIN AUSTRALIA AIRLINES/, 'Virgin Australia'],
        [/^CAPITEQ$/, 'Airnorth (Capiteq Pty Ltd)'],
        [/^NANTAY$/, 'Maroomba Airlines (Nantay Pty Ltd)'],
        [/COMMONWEALTH OF AUSTRALIA (CADETS BRANCH - AIR FORCE)/, 'Australian Air Force Cadets'],
        [/COMMONWEALTH OF AUSTRALIA (DEPARTMENT OF DEFENCE)/, 'Defence Australia'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY RAAF RICHMOND FLYING CLUB/, 'RAAF Richmond Flying Club'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY RAAF RICHMOND GLIDING CLUB/, 'RAAF Richmond Gliding Club'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY ROYAL AUSTRALIAN AIR FORCE 100 SQUADRON/, 'Royal Australian Air Force No. 100 Squadron'],
        [/COMMONWEALTH OF AUSTRALIA REPRESENTED BY ROYAL AUSTRALIAN AIR FORCE/, 'Royal Australian Air Force'],
        [/ROYAL FLYING DOCTOR SERVICE OF AUSTRALIA \((.*)\)/, 'Royal Flying Doctor Service of Australia (\1)'],
        [/ROYAL FLYING DOCTOR SERVICE OF AUSTRALIA CENTRAL OPERATIONS/, 'Royal Flying Doctor Service of Australia (Central Operations)'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY DEPARTMENT OF PLANNING AND ENVIRONMENT/, 'Dept. of Planning and Environment (NSW)'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY NSW POLICE FORCE/, 'New South Wales Police Force'],
        [/STATE OF NEW SOUTH WALES REPRESENTED BY NSW RURAL FIRE SERVICE/, 'New South Wales Rural Fire Service'],
        [/State of South Australia Represented by Department for Environment and Water/, 'Dept. for Environment and Water (SA)'],
        [/STATE OF SOUTH AUSTRALIA REPRESENTED BY SOUTH AUSTRALIA POLICE/, 'South Australia Police'],
        [/STATE OF WESTERN AUSTRALIA REPRESENTED BY DEPARTMENT OF THE PREMIER AND CABINET/, 'Dept. of the Premier and Cabinet (WA)'],
        [/STATE OF WESTERN AUSTRALIA - REPRESENTED BY COMMISSIONER OF POLICE/, 'Western Australia Police Force'],
        [/STATE OF WESTERN AUSTRALIA/, 'Dept. of Biodiversity Conservation and Attractions (WA)'],
      ].freeze

      def self.get_aircraft_manufacturer(manufacturer)
        MANUFACTURER_REPLACEMENT_PATTERNS.each { |p| manufacturer.gsub!(p[0], p[1]) }

        manufacturer_obj = Rails.cache.fetch("aircraft_manufacturer_#{manufacturer}") do
          Manufacturer.find_by(name: manufacturer.titleize)
        end

        raise ActiveRecord::RecordNotFound unless manufacturer_obj

        manufacturer_obj.id
      end

      def self.get_aircraft_type(type_code)
        aircraft_type_obj = Rails.cache.fetch("aircraft_type_typecode_#{type_code}") do
          AircraftType.find_by(type_code: type_code)
        end

        raise ActiveRecord::RecordNotFound unless aircraft_type_obj

        aircraft_type_obj.id
      end

      def self.normalise_name(name)
        name
      end

      def self.normalise_model(input)
        model = input.dup
        AIRCRAFT_MODEL_TO_FAMILY.each { |pattern, replacement| model.gsub!(pattern, replacement) }
        model
      end

      def self.normalise_and_find_operator(input, country:)
        name = input.dup
        OPERATOR_REPLACEMENT_PATTERNS.each { |p| name.gsub!(p[0], p[1]) }
        name = name.titleize
        puts "Searching for #{name}"
        operator = Operator.search(name: name)&.first
        if operator.nil?
          operator = Operator.new(name: name, country: country)
          operator.save(validate: false)
        end

        operator
      end
    end
  end
end
