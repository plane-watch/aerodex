# frozen_string_literal: true

module Processors
  module Manufacturer
    # Processor for importing manufacturer data from ICAO's CFAPPS database.
    #
    # Handles data normalisation including:
    # - Skipping "see X" cross-references
    # - Removing corporate suffixes (SAS, Ltd, GmbH, etc.)
    # - Removing country annotations
    # - Applying known manufacturer name mappings
    #
    # @see ManufacturerNormalisation For normalisation rules and patterns
    class CfappsICAOInt < Processors::Base
      extend ManufacturerNormalisation

      @transform_data = {
        'Code' => {
          function: ->(value) { value&.strip },
          field: 'icao_code'
        },
        'Name' => {
          function: ->(value) { value&.strip },
          field: 'name'
        },
        'Country' => {
          function: ->(value) { value&.strip },
          field: 'country'
        }
      }

      class << self
        def import
          puts 'Importing manufacturer data from ICAO'
          @default_url = 'https://cfapps.icao.int/doc8643/MnfctrerList.cfm'

          source_data = get_source_from_url(@default_url)
          html = Nokogiri::HTML(source_data)
          return false if html.nil?

          table = html.css('table').first
          return false if table.nil?

          # Group rows by manufacturer code
          manufacturer_rows = parse_manufacturer_table(table)

          progress_bar = create_progress_bar(manufacturer_rows.count)
          import_errors = []

          Source::Manufacturer::CfappsICAOIntManufacturerSource.transaction do
            manufacturer_rows.each do |code, names|
              result = import_manufacturer(code, names)
              import_errors << result[:error] if result[:error]
              progress_bar.increment!
            end
          end

          new_import_report(import_errors, manufacturer_rows.count)

          import_errors.empty? || import_errors
        end

        private

        # Parses the HTML table into a hash of code => [names]
        def parse_manufacturer_table(table)
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

          manufacturer_rows
        end

        # Imports a single manufacturer with its alternative names
        def import_manufacturer(code, names)
          # Filter out "see X" cross-references
          filtered_names = names.reject { |n| n.strip.match?(/^see\s+/i) }

          # If all names were cross-references, skip this entry
          return { skipped: true, code: code, reason: 'Cross-reference only' } if filtered_names.empty?

          # Normalise all names and pick the shortest as canonical.
          # This helps avoid picking "Airbus Defence and Space" over "Airbus".
          normalised_candidates = filtered_names.map do |name|
            cleaned = remove_country_annotation(name)
            {
              original: name,
              cleaned: cleaned,
              normalised: normalise_manufacturer_name(cleaned)
            }
          end.reject { |c| c[:normalised].blank? }

          # Skip if we couldn't normalise any names
          return { skipped: true, code: code, reason: 'Could not normalise any names' } if normalised_candidates.empty?

          # Pick the shortest normalised name as canonical
          best_candidate = normalised_candidates.min_by { |c| c[:normalised].length }
          canonical_name = best_candidate[:normalised]

          # Extract country from the best candidate's original name
          country = extract_country_from_name(best_candidate[:original])

          # All other normalised names become alternatives
          alt_names = normalised_candidates
                      .map { |c| c[:normalised] }
                      .reject { |n| n.downcase == canonical_name.downcase }
                      .uniq

          # Also store the original names (cleaned of country) for matching
          original_names = filtered_names.map { |n| remove_country_annotation(n) }.compact.uniq
          alt_names = (alt_names + original_names).uniq.reject { |n| n.downcase == canonical_name.downcase }

          record = Source::Manufacturer::CfappsICAOIntManufacturerSource.find_or_initialize_by(icao_code: code)
          record.assign_attributes(
            name: canonical_name,
            country: country,
            alt_names: alt_names,
            data: { original_names: names },
            import_date: Time.current
          )

          if record.save
            { manufacturer: record }
          else
            { error: { code: code, errors: record.errors.full_messages } }
          end
        end
      end
    end
  end
end
