module Processor
  module Manufacturer
    # Processor for importing manufacturer data from ICAO's CFAPPS database
    class CfappsICAOInt < Processor::Base
      def self.import
        @transform_data = {
          'Code' => {
            function: ->(value) { value&.strip },
            field: 'icao_code',
          },
          'Name' => {
            function: ->(value) { value&.strip },
            field: 'name',
          },
          'Country' => {
            function: ->(value) { value&.strip },
            field: 'country',
          }
        }

        puts 'Importing manufacturer data from ICAO'
        @default_url = 'https://cfapps.icao.int/doc8643/MnfctrerList.cfm'

        source_data = get_source_from_url(@default_url)
        html = Nokogiri::HTML(source_data)
        return false if html.nil?

        table = html.css('table').first
        return false if table.nil?

        # Group rows by manufacturer code
        manufacturer_rows = {}
        current_code = nil

        table.css('tr').each do |row|
          next if row.css('th').any? # Skip header row

          code = row.css('td')[0]&.text&.strip
          full_name = row.css('td')[1]&.text&.strip

          next if full_name.blank?

          # If we have a code, update current_code
          current_code = code if code.present?

          # Skip if we don't have a current code
          next if current_code.nil?

          manufacturer_rows[current_code] ||= []
          manufacturer_rows[current_code] << full_name
        end

        puts manufacturer_rows.inspect

        Source::Manufacturer::CfappsICAOIntManufacturerSource.transaction do
          manufacturer_rows.each do |code, names|
            # Extract country from the first name (it's in parentheses at the end)
            country = nil
            first_name = names.first
            if first_name =~ /\((.*?)\)$/
              country = ::Regexp.last_match(1).strip
              first_name = first_name.gsub(/\s*\(.*?\)$/, '').strip
            end

            # Process alternative names
            alt_names = names[1..-1].map do |name|
              # Remove country from alternative names if present
              name.gsub(/\s*\(.*?\)$/, '').strip
            end

            attributes = {
              'Code' => code,
              'Name' => first_name,
              'Country' => country,
              'AltNames' => alt_names
            }

            transformed_attrs = {}
            attributes.each do |key, value|
              transformed_data = transform_field(key, value)
              next if transformed_data.nil?

              transformed_attrs[transformed_data[:key]] = transformed_data[:value]
            end

            puts transformed_attrs

            record = Source::Manufacturer::CfappsICAOIntManufacturerSource.find_or_initialize_by(icao_code: transformed_attrs['icao_code'])
            record.icao_code = transformed_attrs['icao_code']
            record.name = transformed_attrs['name']
            record.country = transformed_attrs['country']
            record.alt_names = alt_names
            record.data = attributes
            record.import_date = Date.today
            record.save!
          end
        end
      end
    end
  end
end
