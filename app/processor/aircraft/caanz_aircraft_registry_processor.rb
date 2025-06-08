# frozen_string_literal: true

# This processor is used to import aircraft data from the `Civil Aviation Authority of New Zealand`
# aircraft registry
module Processor
  module Aircraft
    class CAANZAircraftRegistryProcessor < Processor::Aircraft::AircraftProcessor
      @transform_data = {
        'Reg Mark' => {
          field: :registration,
        },
        'Man. Model' => {
          function: ->(model) { normalise_model(model)&.id },
          field: :aircraft_type_id,
        },
        'Name and Address' => {
          function: lambda { |v|
            normalise_and_find_operator(v.gsub(/^(.*)\r\n.*$/, '\\1'),
                                        country: 'New Zealand')
          },
          field: :operator,
        },
        'SerialNo' => {
          field: :serial_number,
        },
        'Mode S Code Country/Aircraft' => {
          field: :icao,
          function: ->(v) { extract_icao(v) }
        }
      }

      def self.search(registration)
        search_param = registration.gsub(/^ZK-/, '')
        data = {}
        url = "https://caanz.cwp.govt.nz/aircraft/aircraft-registration/aircraft-register-search/ShowDetails/#{search_param}"

        response = Rails.cache.fetch("CAANZAircraftRegistryProcessor#search/#{search_param}") do
          Excon.get(url,
                    headers: {
                      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:122.0) Gecko/20100101 Firefox/122.0',
                      'Referer' => "https://caanz.cwp.govt.nz/aircraft/aircraft-registration/aircraft-register-search/querymark?Mark=#{search_param}",
                    }, debug: true, omit_default_port: true)
        end

        return false unless response.status == 200

        doc = Nokogiri::HTML(response.body)
        rows = doc.css('.row-header, .row-detail').collect(&:text)
        while rows.any?
          key, value = rows.shift(2)
          transformed_data = transform_row(key, value)
          next if transformed_data.nil?

          data[transformed_data[:key].to_sym] = transformed_data[:value]
        end

        data
      end

      def self.transform_row(a, b)
        key = a&.strip&.gsub(/:$/, '')
        value = b&.strip

        return nil if key.nil? || value.nil?
        return nil if @transform_data[key].nil?

        {
          key: @transform_data[key][:field] || key,
          value: @transform_data[key][:function] ? @transform_data[key][:function].call(value) : value
        }

      end

      def self.extract_icao(input)
        input.split(/\n/).last.split(/\s+/).last
      end

      def self.normalise_model(input)
        tokens = input.split.map.with_index(1) { |_, i| input.split.first(i).join(' ') }
        manufacturer = Manufacturer.where(name: tokens).order('length(name) DESC').first
        return false if manufacturer.nil?

        aircraft_model = input.gsub(/^#{manufacturer.name} /, '')
        AircraftType.joins(:manufacturer).find_by(name: aircraft_model, manufacturer: { name: manufacturer.name })
      end

    end
  end
end