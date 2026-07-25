# frozen_string_literal: true

# == Schema Information
#
# Table name: airport_sources
#
#  id               :integer          not null, primary key
#  icao_code        :string
#  iata_code        :string
#  ident            :string
#  name             :string           not null
#  city             :string
#  municipality     :string
#  country_code     :string
#  latitude         :decimal(9, 6)
#  longitude        :decimal(9, 6)
#  elevation        :decimal(, )
#  timezone         :string
#  airport_type     :string
#  type             :string           not null
#  import_date      :datetime         not null
#  data             :jsonb            default("\"{}\""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#
# Indexes
#
#  index_airport_sources_on_data            (data)
#  index_airport_sources_on_excluded        (excluded)
#  index_airport_sources_on_iata_and_type   (iata_code,type)
#  index_airport_sources_on_icao_and_type   (icao_code,type)
#  index_airport_sources_on_ident_and_type  (ident,type)
#

module Source
  module Airport
    # Base class for airport data sources.
    #
    # Airport sources must have at least one of ICAO code, IATA code, or ident
    # to be valid. The ident field is used by OurAirports as a unique identifier
    # that may differ from ICAO code (e.g., for small US airports).
    class AirportSource < ApplicationRecord
      include MeiliSearch::Rails
      include HasSourceExclusion

      self.table_name = 'airport_sources'

      serialize :data, coder: JsonbSerializer

      validates :name, presence: true
      validate :ensure_identifier_present

      # Scopes for querying by identifier
      scope :with_icao, ->(icao_code) { where(icao_code: icao_code) if icao_code.present? }
      scope :with_iata, ->(iata_code) { where(iata_code: iata_code) if iata_code.present? }
      scope :with_ident, ->(ident) { where(ident: ident) if ident.present? }

      # Find by best available identifier, preferring ICAO over IATA over ident
      scope :find_by_identifier, lambda { |icao: nil, iata: nil, ident: nil|
        if icao.present?
          with_icao(icao)
        elsif iata.present?
          with_iata(iata)
        elsif ident.present?
          with_ident(ident)
        else
          none
        end
      }

      meilisearch do
        attribute :name
        attribute :icao_code
        attribute :iata_code
        attribute :city
      end

      # Returns the location name (city or municipality) for this airport.
      # Subclasses can override this to return the appropriate field.
      #
      # @return [String, nil] The location name
      def location_name
        city.presence || municipality
      end

      private

      # Validates that at least one identifier is present
      def ensure_identifier_present
        return if icao_code.present? || iata_code.present? || ident.present?

        errors.add(:base, 'Airport must have at least one identifier (ICAO code, IATA code, or ident)')
      end
    end
  end
end
