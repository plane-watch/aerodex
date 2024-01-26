require 'csv'

class OpenTransportOperatorProcessor < OperatorProcessor
    @@TRANSFORM_DATA = {
        "3char_code" => {
            function: ->(value) { value&.strip },
            field: 'icao_code',
        },
        "2char_code" => {
            function: ->(value) { value&.strip },
            field: 'iata_code',
        },
        "num_code" => {
            function: ->(value) { value&.strip },
            field: 'num_code',
        },
        "validity_from" => {
            function: ->(value) { value&.strip },
            field: 'validity_from'
        },
        "validity_to" => {
            function: ->(value) { value&.strip },
            field: 'validity_to'
        },
        "name" => {
            function: ->(value) { value&.strip },
            field: 'name'
        },
        "name2" => {
            function: ->(value) { value&.strip },
            field: 'alt_name'
        },
        "wiki_link" => {
            function: ->(value) { value&.strip },
            field: 'wikipedia_link'
        },
        "alt_names" => {
            function: ->(value) { value&.strip },
            field: 'alt_name'
        }
    }

    def self.import
        csv_data = Excon.get('https://raw.githubusercontent.com/opentraveldata/opentraveldata/master/opentraveldata/optd_airlines.csv')&.body
        csv = CSV.parse(csv_data, headers: true, encoding: "utf-8:utf-8", col_sep: "^")

        batch_import_timestamp = DateTime.now()
        is_first_import = OpenTransportOperatorSource.count > 0 ? false : true

        csv&.each do |row|
            attributes = {}

            row.headers.each do |key|
                transformed_data = transform_field(key, row[key])
                next if transformed_data.nil?

                attributes[transformed_data[:key]] = transformed_data[:value]
            end

            # if it's the first time, ignore all invalid records
            next if attributes['validity_to'] != nil and (attributes['validity_to'].to_date < Date.today and is_first_import)
            
            # find the matching operator
            record = self.find_operator(attributes['icao_code'], attributes['iata_code'], attributes['name'], attributes['validity_to'])
            next if record.nil? # operator was already invalid, skip

            # update the details 
            record.data = attributes
            record.icao_code = attributes['icao_code']
            record.iata_code = attributes['iata_code']
            record.name = attributes['name']
            record.import_date = batch_import_timestamp if record.new_record? || record.changed?
            record.save!
        end
    end

    def self.find_operator(icao_code, iata_code, name, validity_to)
        # Need to have at least two matching of ICAO, IATA and Name
        # prefer ICAO, fallback to IATA, check with name
        if icao_code != nil and iata_code != nil
            records = OpenTransportOperatorSource.with_icao(icao_code).with_iata(iata_code)
        elsif icao_code != nil and iata_code == nil
            records = OpenTransportOperatorSource.with_icao_name(icao_code, name)
        elsif icao_code == nil and iata_code != nil
            records = OpenTransportOperatorSource.with_iata_name(iata_code, name)
        end
        
        # no existing record for that ICAO or IATA code and name and it's still valid.
        return OpenTransportOperatorSource.new if (records.nil? || records.count == 0) and (validity_to == nil || validity_to.to_date >= Date.today)

        # only one matching record, but make sure it's not a past-invalid record
        # an airline that's been invalidated since the last import is valid.
        return records.first if records.count == 1 and (validity_to.nil? || validity_to.to_date >= records.first.import_date)
    end
end