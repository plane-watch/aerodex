# == Schema Information
#
# Table name: operator_sources
#
#  id          :bigint           not null, primary key
#  data        :jsonb            not null
#  iata_code   :string
#  icao_code   :string
#  name        :string
#  type        :string           not null
#  import_date :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_operator_sources_on_data  (data) USING gin
#
module Source
  module Operator
    class OperatorSource < ApplicationRecord
      include MeiliSearch::Rails
      
      validate :icao_or_iata_code
      serialize :data, coder: JsonbSerializer

      scope :with_icao, ->(icao_code) { where(icao_code: icao_code) unless icao_code.nil? }
      scope :with_iata, ->(iata_code) { where(iata_code: iata_code) unless iata_code.nil? }
      scope :with_icao_and_name, lambda { |icao_code, name|
        where(icao_code: icao_code, name: name) unless icao_code.nil? || name.nil?
      }
      scope :with_iata_and_name, lambda { |iata_code, name|
        where(iata_code: iata_code, name: name) unless iata_code.nil? || name.nil?
      }

      scope :find_unique_operator, lambda { |args|
        if args['icao_code'] && (args['iata_code'] || args['name'])
          raise ArgumentError, 'ICAO and IATA/Name must be exclusive'
        end

        unscoped
          .with_icao(args['icao_code'])
          .with_iata_and_name(args['iata_code'], args['name'])
      }

      private

      def icao_or_iata_code
        errors.add(:base, 'Record must have one of ICAO or IATA code.') unless icao_code || iata_code
      end
    end
  end
end
