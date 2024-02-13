require 'csv'

class OpenskyManufacturerProcessor < Processor
  @transform_data = {
    'Code' => {
      function: ->(value) { value&.strip },
      field: 'icao_code',
    },
    'Name' => {
      function: ->(value) { value&.strip },
      field: 'name',
    }
  }

  DEFAULT_URL = 'https://opensky-network.org/datasets/metadata/doc8643Manufacturers.csv'

  def self.import(url = DEFAULT_URL)
    csv_data = get_source_from_url(url)
    return false if csv_data.nil?

    csv = CSV.parse(csv_data, headers: true, encoding: 'utf-8:utf-8', col_sep: ',', liberal_parsing: true)

    import_errors = []

    OpenskyManufacturerSource.transaction do
      csv&.each do |row|
        attributes = {}

        row.headers.each do |key|
          transformed_data = transform_field(key, row[key])
          next if transformed_data.nil?

          attributes[transformed_data[:key]] = transformed_data[:value]
        end

        puts attributes

        if attributes['name'].present? && attributes['icao_code'].present?
          OpenskyManufacturerSource.create!(name: attributes['name'], icao_code: attributes['code'])
        end
      end
    end
  end
end
