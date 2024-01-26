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
class OperatorSource < ApplicationRecord
    validate :icao_or_iata_code
    serialize :data, JsonbSerializer

    scope :with_icao, ->(icao_code) { where(icao_code: icao_code) unless icao_code.nil? }
    scope :with_iata, ->(iata_code) { where(iata_code: iata_code) unless iata_code.nil? }
    scope :with_icao_name, -> (icao_code, name) { where(icao_code: icao_code, name: name) unless icao_code.nil? || name.nil?}
    scope :with_iata_name, ->(iata_code, name) { where(iata_code: iata_code, name: name) unless iata_code.nil? || name.nil? }

    scope :find_unique_operator, ->(args) do
        raise ArgumentError.new('ICAO and IATA/Name must be exclusive') if args['icao_code'] && (args['iata_code'] || args['name'])
        unscoped
            .with_icao(args['icao_code'])
            .with_iata_name(args['iata_code'], args['name'])
    end

    private

    def icao_or_iata_code
        errors.add(:missing_code, "Record must have one of ICAO or IATA code.") unless self.icao_code || self.iata_code
    end
end
