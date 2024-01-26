require 'csv'

class VRSDataOperatorProcessor < OperatorProcessor

  @@TRANSFORM_DATA = {
    'Name' => {
      function: ->(value) { normalise_name(value) },
      field: 'name'
    },
    'ICAO' => {
      function: ->(value) { value.blank? ? nil : value.strip },
      field: 'icao_code',
    },
    'IATA' => {
      function: ->(value) { value&.strip },
      field: 'iata_code',
    },
    'PositioningFlightPattern' => {
      function: ->(value) { value.blank? ? nil : value.strip },
      field: 'positioning_callsign_pattern',
    },
    'CharterFlightPattern' => {
      function: ->(value) { value.blank? ? nil : value.strip },
      field: 'charter_callsign_pattern',
    }
  }

  def self.import
    csv_data = Excon.get('https://raw.githubusercontent.com/vradarserver/standing-data/main/airlines/schema-01/airlines.csv')&.body

    csv = CSV.parse(csv_data, headers: true, encoding: "utf-8:utf-8")

    batch_import_timestamp = DateTime.now()

    csv&.each do |row|
      attributes = {}
      row.headers.each do |key|
        transformed_data = transform_field(key, row[key])
        next if transformed_data.nil?

        attributes[transformed_data[:key]] = transformed_data[:value]
      end

      search_params = attributes.dup.slice *%w(icao_code iata_code name)
      search_params.except!(*%w(name iata_code)) if search_params['icao_code']

      record = VRSDataOperatorSource.find_unique_operator(search_params).first_or_initialize

      record.data = attributes
      record.icao_code = attributes['icao_code']
      record.iata_code = attributes['iata_code']
      record.name = attributes['name']
      record.import_date = batch_import_timestamp if record.new_record? || record.changed?
      record.save!
    end
  end
end