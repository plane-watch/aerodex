require 'csv'

class StandingDataOperatorGateway < OperatorGateway

  TRANSFORM_DATA = {
    'Name' => {
      function: ->(value) { normalise_name(value) },
      field: :name
    },
    'ICAO' => {
      function: ->(value) { value&.strip },
      field: :icao_callsign,
    },
    'IATA' => {
      function: ->(value) { value&.strip },
      field: :iata_callsign,
    },
    'PositioningFlightPattern' => {
      function: ->(value) { value.blank? ? nil : value.strip },
      field: :positioning_callsign_pattern,
    },
    'CharterFlightPattern' => {
      function: ->(value) { value.blank? ? nil : value.strip },
      field: :charter_callsign_pattern,
    }
  }

  def self.import
    csv_data = Excon.get('https://raw.githubusercontent.com/vradarserver/standing-data/main/airlines/schema-01/airlines.csv')&.body
    # csv_data.gsub!("\xEF\xBB\xBF".force_encoding("ASCII-8BIT"), '')

    csv = CSV.parse(csv_data, headers: true, encoding: "utf-8:utf-8")

    csv&.each do |row|
      attributes = {}
      row.headers.each do |key|
        transformed_data = transform_field(key, row[key])
        next if transformed_data.nil?

        attributes[transformed_data[:key]] = transformed_data[:value]
      end
      operator = Operator.find_or_initialize_by(icao_callsign: attributes[:icao_callsign])
      operator.attributes = attributes
      operator.save

    end
  end

  def self.normalise_name(name)
    OPERATOR_REWRITE_PATTERNS.each { |p| name.gsub!(p[0], p[1]) }
    name
  end

  def self.transform_field(key, value)

    if TRANSFORM_DATA[key].nil?
      return nil
    end

    {
      key: TRANSFORM_DATA[key][:field] || key,
      value: TRANSFORM_DATA[key][:function] ? TRANSFORM_DATA[key][:function].call(value) : value
    }

  end

end