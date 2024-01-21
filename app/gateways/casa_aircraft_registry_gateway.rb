class CASAAircraftRegistryGateway < AircraftGateway

  CHARACTER_SET = ('A'..'Z').to_a + ('0'..'9').to_a

  TRANSFORM_DATA = {
    'Aircraft model' => {
      function: ->(v) { self.get_aircraft_model(v) },
      field: :aircraft_type_id,
    },
    'Date first registered' => {
      function: ->(v) { Date.parse(v) },
      field: :registration_date,
    },
    'Serial' => {
      field: :serial_number
    },
    'Registration holder' => {
      function: ->(v) { normalise_name(v) },
      field: :owner,
    },
    'Registered operator' => {
      function: ->(v) { Operator.search(v).first },
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

  def self.search(registration)
    data = {
      registration: registration,
      icao: reg_to_hex(registration),
      registration_country: 'Australia'
    }

    search_param = registration.gsub(/^VH-/, '')

    url = "https://www.casa.gov.au/search-centre/aircraft-register/#{search_param.downcase}"
    response = Rails.cache.fetch("CasaAircraftRegistryGateway#search/#{search_param}") do
      Excon.get(url)
    end

    document = Nokogiri.parse(response.body)
    document.css('fieldset > div > div.field > div').each_slice(2) do |a, b|
      transformed_data = transform_row(a, b)
      next if transformed_data.nil?

      data[transformed_data[:key].to_sym] = transformed_data[:value]
    end
    data
  end

  def self.transform_row(a, b)
    key = a&.text&.strip&.gsub(/:$/, '')
    value = b&.text&.strip

    return nil if key.nil? || value.nil?

    if TRANSFORM_DATA[key].nil?
      return nil
    end

    {
      key: TRANSFORM_DATA[key][:field] || key,
      value: TRANSFORM_DATA[key][:function] ? TRANSFORM_DATA[key][:function].call(value) : value
    }

  end

  def self.get_aircraft_manufacturer(manufacturer)
    MANUFACTURER_REPLACEMENT_PATTERNS.each { |p| manufacturer.gsub!(p[0], p[1]) }

    _manufacturer_obj = Rails.cache.fetch("aircraft_manufacturer_#{manufacturer}") do
      Manufacturer.find_by(name: manufacturer.titleize)
    end

    raise ActiveRecord::RecordNotFound unless _manufacturer_obj

    _manufacturer_obj.id
  end

  def self.get_aircraft_model(model)
    search_term = model.dup
    AIRCRAFT_MODEL_TO_FAMILY.each { |p| search_term.gsub!(p[0], p[1]) }
    _aircraft_type_obj = Rails.cache.fetch("aircraft_model_#{search_term}") do
      AircraftType.find_by(name: search_term)
    end

    raise ActiveRecord::RecordNotFound unless _aircraft_type_obj

    _aircraft_type_obj.id

  end

  def self.normalise_name(name)
    name
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