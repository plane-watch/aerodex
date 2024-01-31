# frozen_string_literal: true

# This processor is used to import aircraft data from the CASA aircraft registry
# https://www.casa.gov.au/aircraft-register-search

class CASAAircraftRegistryProcessor < AircraftProcessor
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

  def self.bulk_import(registrations: [])
    errors = []
    success = []
    registrations.each do |reg|
      reg = "VH-#{reg}" unless reg =~ /^VH-/
      puts reg
      aircraft = nil
      begin
        aircraft = CASAAircraftRegistryProcessor.search(reg)
      rescue ActiveRecord::RecordNotFound
        errors << { registration: reg, errors: 'Aircraft type not found' }
      end
      puts aircraft.inspect
      next if aircraft.nil? || aircraft[:registration].nil?

      obj = Aircraft.find_or_initialize_by(
        registration: aircraft[:registration],
        serial_number: aircraft[:serial_number],
        aircraft_type_id: aircraft[:aircraft_type_id])
      obj.assign_attributes(aircraft)
      begin
        obj.save!
        success << reg
      rescue ActiveRecord::RecordInvalid
        errors << { registration: aircraft[:registration], errors: obj.errors.full_messages }
        next
      end
    end
    { success: success, errors: errors }
  end

  def self.search(registration)
    search_param = registration.gsub(/^VH-/, '')
    data = {}
    url = "https://www.casa.gov.au/search-centre/aircraft-register/#{search_param.downcase}"

    response = Rails.cache.fetch("CasaAircraftRegistryProcessor#search/#{search_param}") do
      Excon.get(url)
    end

    document = Nokogiri.parse(response.body)
    document.css('fieldset > div > div.field > div').each_slice(2) do |a, b|
      transformed_data = transform_row(a, b)
      next if transformed_data.nil?

      data[transformed_data[:key].to_sym] = transformed_data[:value]
    end
    data.merge({
                 registration: registration,
                 icao: reg_to_hex(registration),
                 registration_country: 'Australia'
               })

  end

  def self.transform_row(a, b)
    key = a&.text&.strip&.gsub(/:$/, '')
    value = b&.text&.strip

    return nil if key.nil? || value.nil?
    return nil if @transform_data[key].nil?

    {
      key: @transform_data[key][:field] || key,
      value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
    }

  end

  def self.hex_to_reg(hex_code)
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

  def self.reg_to_hex(registration)
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