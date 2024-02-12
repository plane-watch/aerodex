require 'csv'

class OpenTransportOperatorProcessor < OperatorProcessor
  @transform_data = {
    '3char_code' => {
      function: ->(value) { value&.strip },
      field: 'icao_code',
    },
    '2char_code' => {
      function: ->(value) { value&.strip },
      field: 'iata_code',
    },
    'num_code' => {
      function: ->(value) { value&.strip },
      field: 'num_code',
    },
    'validity_from' => {
      function: ->(value) { value&.strip },
      field: 'validity_from'
    },
    'validity_to' => {
      function: ->(value) { value&.strip },
      field: 'validity_to'
    },
    'name' => {
      function: ->(value) { value&.strip },
      field: 'name'
    },
    'name2' => {
      function: ->(value) { value&.strip },
      field: 'alt_name'
    },
    'wiki_link' => {
      function: ->(value) { value&.strip },
      field: 'wikipedia_link'
    },
    'alt_names' => {
      function: ->(value) { parse_alt_names_to_a(value) if value.present? },
      field: 'alt_names'
    }
  }

  DEFAULT_URL = 'https://raw.githubusercontent.com/opentraveldata/opentraveldata/master/opentraveldata/optd_airlines.csv'

  def self.import(url = DEFAULT_URL)
    csv_data = get_source_from_url(url)
    return false if csv_data.nil?

    csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8', col_sep: '^')

    batch_import_timestamp = DateTime.now
    is_first_import = OpenTransportOperatorSource.none?
    records_processed = 0

    import_errors = []

    OpenTransportOperatorSource.transaction do
      csv&.each do |row|
        attributes = {}

        # pre-process and throw away anything that isn't an airline.
        next unless row['pk'] =~ /\Aair-/

        row.headers.each do |key|
          transformed_data = transform_field(key, row[key])
          next if transformed_data.nil?

          attributes[transformed_data[:key]] = transformed_data[:value]
        end

        # if it's the first time, ignore all invalid records
        next if is_first_import && attributes['validity_to']&.to_date&.past?

        # find the matching operator
        record = find_operator icao_code: attributes['icao_code'], iata_code: attributes['iata_code'],
                               name: attributes['name'], validity_to: attributes['validity_to']

        next if record.nil? # operator was already invalid, skip

        # update the details
        record.attributes = {
          icao_code: attributes['icao_code'],
          iata_code: attributes['iata_code'],
          name: attributes['name'],
          data: attributes,
        }
        record.import_date = batch_import_timestamp if record.new_record? || record.changed?

        records_processed += 1

        if record.valid?
          record.save
        else
          import_errors.append record.errors
        end
      end
    end

    new_import_report(import_errors, records_processed)
  end

  def self.find_operator(icao_code:, iata_code:, name:, validity_to:)
    # Need to have at least two matching of ICAO, IATA and Name
    # prefer ICAO, fallback to IATA, check with name
    records = if icao_code.present? && iata_code.present?
                Rails.logger.debug('with_icao, with_iata')
                OpenTransportOperatorSource.with_icao(icao_code).with_iata(iata_code)
              elsif icao_code.present?
                Rails.logger.debug('with_icao_and_name')
                OpenTransportOperatorSource.with_icao_and_name(icao_code, name)
              elsif iata_code.present?
                Rails.logger.debug('with_iata_and_name')
                OpenTransportOperatorSource.with_iata_and_name(iata_code, name)
              else
                OpenTransportOperatorSource.none
              end

    validity_to_date = validity_to&.to_date

    # only one matching record, but make sure it's not a past-invalid record
    # an airline that's been invalidated since the last import is valid.
    if records.count == 1 && (validity_to_date.nil? || validity_to_date >= records.first&.import_date)
      return records.first
    end

    # no existing record for that ICAO or IATA code and name and it's still valid.
    return unless records&.none? && (validity_to_date.nil? || validity_to_date >= Date.today)

    OpenTransportOperatorSource.new
  end

  def self.parse_alt_names_to_a(value)
    # example format:
    # en|PAL Express|=en|Air Philippines Corporation|=en|Air Philippines|h=en|Airphil Express|h=sign|AIRPHIL|
    # `en` = 2 letter ISO language code
    # `\=` means a terminator?
    # `sign` = call sign
    # `abbr` = abbreviation
    alt_names = value.split('|')
    junk = []
    # deal with `abbr` and `sign` first
    # remove the item afterwards as it's not an alternate name
    alt_names.each_with_index do |name, idx|
      junk.append(idx + 1) if name.include? 'sign'
      junk.append(idx + 1) if name.include? 'abbr'
    end
    junk.each { |idx| alt_names.delete_at (idx) }

    # remove other junk or tokens smaller than 3 chars
    alt_names.delete_if { |name| name.include? '=' }
    alt_names.delete_if { |name| name.length < 3 }
    alt_names
  end
end
