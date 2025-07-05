module Processor
  module Country
    class Country < Processor::Base
      def self.combine_sources
        Source::Country::OpenTravelCountrySource.find_each do |source|
          ::Country.find_or_initialize_by(iso_2char_code: source.iso_2char_code).tap do |country|
            country.iso_2char_code = source.iso_2char_code
            country.iso_3char_code = source.iso_3char_code
            country.iso_num_code = source.iso_num_code
            country.name = source.name
            country.capital = source.capital
            country.save!
          end
        end
      end
    end
  end
end
