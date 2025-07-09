module Processors
  module Manufacturer
    class Manufacturer < Processors::Base
      def self.combine_sources
        Source::Manufacturer::CfappsICAOIntManufacturerSource.find_each do |source|
          ::Manufacturer.find_or_initialize_by(icao_code: source.icao_code).tap do |manufacturer|
            manufacturer.icao_code = source.icao_code
            manufacturer.name = source.name
            if source.country.present?
              # Try exact match first
              country = ::Country.find_by(name: source.country)

              # If no exact match, try case-insensitive match
              country ||= ::Country.where('LOWER(name) = ?', source.country.downcase).first

              # If still no match, try partial match
              country ||= ::Country.where('LOWER(name) LIKE ?', "%#{source.country.downcase}%").first

              manufacturer.country = country if country.present?
            end
            manufacturer.alt_names = source.alt_names
            manufacturer.save!
          end
        end
      end
    end
  end
end
