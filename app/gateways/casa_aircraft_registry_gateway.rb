class CASAAircraftRegistryGateway < AircraftGateway

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
      icao: registration_to_hex(registration)
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
    puts "Searching for: #{search_term}"
    _aircraft_type_obj = Rails.cache.fetch("aircraft_model_#{search_term}") do
      AircraftType.find_by(name: search_term)
    end

    raise ActiveRecord::RecordNotFound unless _aircraft_type_obj

    _aircraft_type_obj.id

  end

  def self.normalise_name(name)
    name
  end

  def self.hex_to_rego(hex_code)
    hex_code.sub!(/^7c/i, '')

    return false if hex_code =~ /^[cf]/i

    dec = hex_code.to_i(16)

    l1, l1_dec, l2, l2_dec, l23_dec, l3, l3_dec = ''

    if dec >= 1296
      l1_dec = dec / 1296
      l23_dec = dec - (1296 * l1_dec)
      l1 = (65 + l1_dec).chr
    else
      l1 = 'A'
      l23_dec = dec
    end

    if l23_dec >= 36
      l2_dec = l23_dec / 36
      l3_dec = l23_dec - (36 * l2_dec)
      l2 = (65 + l2_dec).chr
    else
      l2 = 'A'
      l3_dec = l23_dec
    end

    l3 = (65 + l3_dec).chr

    "VH-#{l1}#{l2}#{l3}"
  end

  def self.registration_to_hex(registration)
    return false unless registration =~ /^VH\-[A-Z]{3}$/

    l1, l2, l3 = registration[3..-1].chars.map { |c| c.ord - 65 }

    l1_dec = l1 * 1296
    l2_dec = l2 * 36
    l3_dec = l3

    dec = l1_dec + l2_dec + l3_dec
    hex_code = dec.to_s(16).upcase

    "7C#{hex_code}"
  end
end